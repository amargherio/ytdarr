# Configuration Reference

Ytdarr stores application configuration in its SQLite database and exposes it through the **Settings UI** at `/settings` unless noted otherwise. The Settings UI is organized into **Media Management**, **Profiles**, **YouTube**, **Download**, **General**, and **System** categories.

## 1. Overview

- Configuration is stored in a SQLite database and managed through the Settings UI.
- On first startup, supported environment variables can bootstrap database values.
- A non-empty `YTDARR_YOUTUBE_API_KEY` always takes precedence over the browser-managed API key.
- The Settings UI identifies whether a value is database-managed, environment-managed, stored only, immediately effective, scheduled, or restart-required.
- Deployment settings and secrets remain read-only in the browser.

## 2. YouTube Settings

**Location:** Settings UI → **YouTube**

| Setting | Key | Default | Effect | Description |
| --- | --- | --- | --- | --- |
| API Key | `youtube.primary_api_key` | — | Immediate or environment-managed | Required YouTube Data API v3 key. `YTDARR_YOUTUBE_API_KEY` overrides the database value; `YTDARR_YOUTUBE_API_KEY_FILE` can bootstrap an empty database value at startup. |
| Region | `youtube.region` | `US` | Stored only | ISO 3166-1 alpha-2 country code reserved for future region-aware API requests. |

The browser can test the effective credentials with a minimal YouTube API request. The stored secret is never displayed.

### API Quota

The YouTube Data API provides **10,000 units/day** for free. Typical operations cost:

- Channel lookup: 1 unit
- Playlist items list: 1 unit per page (50 items)
- Video details: 1 unit per 50 videos
- Search: 100 units per request

Ytdarr tracks quota usage internally and uses batched API calls to minimize consumption.

## 3. Media Settings

**Location:** Settings UI → **Media Management**

| Setting | Key | Default | Effect | Description |
| --- | --- | --- | --- | --- |
| File Naming Template | `media.file_naming_template` | `%(channel)s/%(title)s.%(ext)s` | Stored only | Intended template for a future configurable naming pipeline. Current downloads use Ytdarr's built-in series and episode naming. |
| Move Strategy | `media.move_strategy` | `hardlink` | Stored only | Intended file placement behavior: `hardlink`, `copy`, or `move`. Current downloads write directly to the destination path. |
| Clean Orphans | `media.clean_orphans` | `true` | Stored only | Intended automatic orphan cleanup policy. Automated cleanup is not active yet. |

### Media Root Folders

Managed through the Settings UI. Each folder has the following fields:

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `path` | string | — | Absolute filesystem path (must exist and be writable). |
| `purpose` | string | `videos` | Content type: `videos`, `music`, `podcasts`. |
| `active` | boolean | `true` | Whether this folder is currently in use. |

- At least one active folder is needed for newly derived channel paths.
- If no folder is configured, Ytdarr defaults to `/downloads`.
- Multiple folders can be configured; the first active one is used for new channels.
- Paths must be absolute, exist on the Ytdarr host, be directories, and be writable.
- Changing a root folder does not migrate existing channel paths or files.

## 4. Quality Profiles

**Location:** Settings UI → **Profiles**

Quality profiles record intended video quality preferences. You can create multiple profiles and mark one as the default. The current downloader does not consume profiles yet, so the UI labels them **Stored only**.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | — | Unique profile name (for example, `1080p` or `Best Quality`). |
| `max_height` | integer | — | Maximum video height in pixels (for example, `720`, `1080`, `2160`). |
| `max_bitrate_kbps` | integer | — | Maximum video bitrate in kbps. |
| `preferred_codecs` | string[] | `[]` | Ordered list of preferred codecs (for example, `["av1", "h264"]`). |
| `allow_hdr` | boolean | `true` | Whether HDR content is acceptable. |
| `format_selector` | string | — | Advanced yt-dlp format selector string (for example, `bestvideo[height<=1080]+bestaudio/best`). |
| `is_default` | boolean | `false` | Marks the profile as the default. Only one profile can be default at a time. |

Setting a profile as default automatically clears the default flag from all other profiles.

## 5. yt-dlp Parameter Sets

**Location:** Settings UI → **Download**

Parameter sets control part of how yt-dlp is invoked. You can create multiple sets for different use cases.

| Field | Type | Default | Effect | Description |
| --- | --- | --- | --- | --- |
| `name` | string | — | Immediate | Unique set name (for example, `Default` or `Slow and Steady`). |
| `format` | string | — | New download jobs | yt-dlp `-f` format string (for example, `bestvideo+bestaudio`). |
| `extra_args` | string | — | New download jobs | Additional yt-dlp arguments, space-separated (for example, `--no-playlist --quiet`). |
| `rate_limit_kbps` | integer | — | Stored only | Intended download speed limit in kbps. |
| `concurrency` | integer | — | Stored only | Intended maximum concurrent downloads for this set. |
| `is_default` | boolean | `false` | Immediate | Marks the set as the default. Only one set can be default at a time. |

### Base parameters

These parameters are always applied regardless of the selected parameter set:

```text
--embed-chapters
--embed-thumbnails
--embed-subs
--write-auto-subs
--merge-output-format mp4
--mtime
```

When a default parameter set exists:

- Its `format` value is passed as `-f <format>` to yt-dlp.
- Its `extra_args` value is split on whitespace and appended to the command.

## 6. Sync Settings

**Location:** Settings UI → **General**

| Setting | Key | Default | Effect | Description |
| --- | --- | --- | --- | --- |
| Sync Interval | `sync_interval_minutes` | `60` | Next scheduling cycle | Minutes between automatic batch syncs of all monitored content. |

### How Sync Works

#### Automatic (`BatchSyncWorker`)

- Starts automatically 2 minutes after application boot.
- Runs on the configured interval (default: every 60 minutes).
- Syncs all monitored channels and playlists in parallel (2 concurrent).
- Uses incremental sync when possible by fetching only content newer than `last_checked_at`.
- Falls back to full sync on first check or when forced.
- Self-reschedules after each run.

#### Manual (`SyncWorker`)

- Triggered by the **Refresh channel data** button in the channel detail view.
- Syncs a single channel or playlist on demand.
- Always performs a full sync regardless of `last_checked_at`.

#### Channel sync fetches

- Channel metadata (avatar, banner, uploads playlist ID)
- All playlists for the channel
- All videos from the uploads playlist
- Creates database records for new videos

#### Playlist sync fetches

- Playlist video list and metadata
- Creates video records for any new videos
- Creates playlist↔video associations
- Does **not** auto-queue downloads; it only imports metadata

## 7. Oban Job Queues

Ytdarr uses Oban for background job processing. The Oban Web dashboard is available at `/oban`.

| Queue | Concurrency | Purpose |
| --- | --- | --- |
| `video_downloader` | 2 | yt-dlp video download jobs |
| `sync_worker` | 5 | User-initiated sync jobs (one per channel or playlist) |
| `batch_sync` | 1 | Scheduled batch sync (singleton — only one runs at a time) |
| `default` | 10 | General purpose queue |

- Failed jobs are retried up to 3 times with backoff.
- The `batch_sync` queue uses a 5-minute uniqueness window to prevent duplicate runs.

## 8. Application Settings Reference

This is the user-facing list of key/value settings stored in the `app_settings` table. Internal quota bookkeeping keys are not shown here.

| Key | Type | Default | Effect |
| --- | --- | --- | --- |
| `youtube.primary_api_key` | string | — | Immediate unless environment-managed |
| `youtube.region` | string | `US` | Stored only |
| `media.file_naming_template` | string | `%(channel)s/%(title)s.%(ext)s` | Stored only |
| `media.move_strategy` | string | `hardlink` | Stored only |
| `media.clean_orphans` | boolean | `true` | Stored only |
| `sync_interval_minutes` | integer | `60` | Next scheduling cycle |

Settings can be viewed and modified via:

- **Settings UI** at `/settings` (recommended)
- **Ash Admin** at `/admin` (development only)
- **IEx console**: `Ytdarr.Settings.put_setting("key", "value")`

## 9. Environment Variables

Environment variables are primarily intended for production deployment bootstrap. See the [Installation Guide](installation.md) for the complete list.

Key behavior:

- A non-empty `YTDARR_YOUTUBE_API_KEY` overrides the browser-managed API key.
- `YTDARR_YOUTUBE_API_KEY_FILE` bootstraps the database only when no API key is already stored.
- `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET`, and the YouTube API key accept a corresponding `*_FILE` variable for Docker/Podman secrets or systemd credentials.
- Set either the direct variable or its `*_FILE` form, never both.

## 10. System Settings

**Location:** Settings UI → **System**

System shows read-only deployment values and capability checks, including:

- Ytdarr version and runtime environment
- public host and HTTP port
- database path and pool size
- Oban queue concurrency
- yt-dlp availability
- database connectivity
- active root-folder health

Secret values are never displayed. Restart-required values must be changed in the deployment environment.

The current settings route is intended for trusted local networks. Do not expose it directly to untrusted clients until application authorization is enabled.
