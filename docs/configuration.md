# Configuration Reference

Ytdarr stores application configuration in its SQLite database and exposes it through the **Settings UI** at `/settings` unless noted otherwise. The Settings UI is organized into the **Media**, **Profiles**, **YouTube**, and **Downloader** tabs.

## 1. Overview

- Configuration is stored in a SQLite database and managed through the Settings UI.
- On first startup, supported environment variables are loaded into the database as a one-time bootstrap.
- After a setting exists in the database, the database value takes precedence over environment variables.
- `YTDARR_YOUTUBE_API_KEY` is the one exception: when it is set and non-empty, it always overrides the database value at runtime.

## 2. YouTube Settings

**Location:** Settings UI → **YouTube** tab

| Setting | Key | Default | Description |
| --- | --- | --- | --- |
| API Key | `youtube.primary_api_key` | — | Required. YouTube Data API v3 key. Can be set via `YTDARR_YOUTUBE_API_KEY` environment variable. |
| Region | `youtube.region` | `US` | ISO 3166-1 alpha-2 country code for API requests. Affects search results and content availability. |

### API Quota

The YouTube Data API provides **10,000 units/day** for free. Typical operations cost:

- Channel lookup: 1 unit
- Playlist items list: 1 unit per page (50 items)
- Video details: 1 unit per 50 videos
- Search: 100 units per request

Ytdarr tracks quota usage internally and uses batched API calls to minimize consumption.

## 3. Media Settings

**Location:** Settings UI → **Media** tab

| Setting | Key | Default | Description |
| --- | --- | --- | --- |
| File Naming Template | `media.file_naming_template` | `%(channel)s/%(title)s.%(ext)s` | Template for downloaded file naming. |
| Move Strategy | `media.move_strategy` | `hardlink` | How files are placed: `hardlink`, `copy`, or `move`. |
| Clean Orphans | `media.clean_orphans` | `true` | Automatically clean up orphaned files. |

### Media Root Folders

Managed through the Settings UI. Each folder has the following fields:

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `path` | string | — | Absolute filesystem path (must exist and be writable). |
| `purpose` | string | `videos` | Content type: `videos`, `music`, `podcasts`. |
| `active` | boolean | `true` | Whether this folder is currently in use. |

- At least one active folder is needed for downloads to work.
- If no folder is configured, Ytdarr defaults to `/downloads`.
- Multiple folders can be configured; the first active one is used for new channels.

## 4. Quality Profiles

**Location:** Settings UI → **Profiles** tab

Quality profiles control video download quality. You can create multiple profiles and mark one as the default.

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

**Location:** Settings UI → **Downloader** tab

Parameter sets control how yt-dlp is invoked. You can create multiple sets for different use cases.

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | string | — | Unique set name (for example, `Default` or `Slow and Steady`). |
| `format` | string | — | yt-dlp `-f` format string (for example, `bestvideo+bestaudio`). |
| `extra_args` | string | — | Additional yt-dlp arguments, space-separated (for example, `--no-playlist --quiet`). |
| `rate_limit_kbps` | integer | — | Download speed limit in kbps (unset = unlimited). |
| `concurrency` | integer | — | Maximum concurrent downloads for this set. |
| `is_default` | boolean | `false` | Marks the set as the default. Only one set can be default at a time. |

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

| Setting | Key | Default | Description |
| --- | --- | --- | --- |
| Sync Interval | `sync_interval_minutes` | `60` | Minutes between automatic batch syncs of all monitored content. |

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

This is the complete list of key/value settings stored in the `app_settings` table.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `youtube.primary_api_key` | string | — | YouTube Data API v3 key |
| `youtube.region` | string | `US` | API region code |
| `media.file_naming_template` | string | `%(channel)s/%(title)s.%(ext)s` | File naming template |
| `media.move_strategy` | string | `hardlink` | File placement strategy |
| `media.clean_orphans` | boolean | `true` | Auto-clean orphaned files |
| `sync_interval_minutes` | integer | `60` | Batch sync interval in minutes |
| `yt_dlp.default_param_set_name` | string | (auto) | Name of the default yt-dlp parameter set |

Settings can be viewed and modified via:

- **Settings UI** at `/settings` (recommended)
- **Ash Admin** at `/admin` (development only)
- **IEx console**: `Ytdarr.Settings.put_setting("key", "value")`

## 9. Environment Variables

Environment variables are primarily intended for production deployment bootstrap. See the [Installation Guide](installation.md) for the complete list.

Key behavior:

- `YTDARR_YOUTUBE_API_KEY` is the only environment variable that actively overrides a database value at runtime.
- All other environment variables are one-time bootstrap values: they are loaded into the database on first startup, after which the database value is authoritative.
