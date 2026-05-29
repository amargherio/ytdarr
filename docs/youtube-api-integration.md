# YouTube API Integration

This document describes how Ytdarr integrates with the YouTube Data API v3,
the quota optimization strategies in place, and operational guidance for
monitoring API usage.

## Architecture Overview

Ytdarr's YouTube integration is a three-layer stack:

```
┌───────────────────────────────────────────────────┐
│  Workers (BatchSyncWorker / SyncWorker)           │  Orchestration & scheduling
│  Content Domain (Ytdarr.Content)                  │  Business logic & persistence
├───────────────────────────────────────────────────┤
│  Client (Ytdarr.Services.YouTube.Client)          │  Batching, pagination, caching
├───────────────────────────────────────────────────┤
│  API    (Ytdarr.Services.YouTube.API)             │  HTTP calls via Req, quota tracking
├───────────────────────────────────────────────────┤
│  QuotaTracker (GenServer)                         │  Daily budget accounting
└───────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Module | Role |
|-------|--------|------|
| **API** | `Ytdarr.Services.YouTube.API` | Thin HTTP wrapper around each YouTube endpoint. Accepts params, makes `Req.get/2` calls, parses responses into `Models.APIResponse` structs, and records quota usage via `QuotaTracker`. |
| **Client** | `Ytdarr.Services.YouTube.Client` | High-level operations: pagination, batch splitting (50-item chunks), incremental sync with early termination, video detail caching. Composes multiple API calls into logical operations. |
| **Content** | `Ytdarr.Content` | Ash domain that orchestrates full channel/playlist syncs: metadata refresh, uploads sync, playlist discovery, video upsert, and PlaylistVideo link creation. |
| **Workers** | `BatchSyncWorker`, `SyncWorker` | Oban workers. `BatchSyncWorker` handles scheduled sync of all monitored content. `SyncWorker` handles user-initiated single-item syncs. Both perform pre-flight quota checks. |
| **QuotaTracker** | `Ytdarr.Services.YouTube.QuotaTracker` | GenServer tracking daily quota usage. Persists to database, resets at midnight Pacific Time, provides `can_afford?/2` and `estimate_batch_cost/2` for budget decisions. |

## YouTube Data API v3 Quota Model

YouTube allocates **10,000 quota units per day** per Google Cloud project,
resetting at **midnight Pacific Time**.

### Quota Costs by Operation

| Operation | YouTube Endpoint | `part` Parameter | Cost |
|-----------|-----------------|------------------|------|
| Search channels | `search.list` | `snippet` | **100 units** |
| Get channel | `channels.list` | `snippet,contentDetails,brandingSettings` | 1 unit |
| Get channels (batch) | `channels.list` (up to 50 IDs) | `snippet,contentDetails,brandingSettings` | 1 unit |
| List playlists | `playlists.list` | `snippet,contentDetails` | 1 unit |
| Get playlists (batch) | `playlists.list` (up to 50 IDs) | `snippet,contentDetails` | 1 unit |
| List playlist items | `playlistItems.list` (up to 50 items) | `snippet,contentDetails` | 1 unit |
| Get video details | `videos.list` (up to 50 IDs) | `snippet,contentDetails` | 1 unit |

> **Key insight:** Read operations cost 1 unit regardless of how many items are
> returned (up to the 50-item page limit). Batching items into a single request
> is the primary optimization lever. Search is 100× more expensive than a read.

### Typical Usage Scenarios

| Scenario | Estimated Cost | Notes |
|----------|---------------|-------|
| Add a new channel (search + metadata) | ~101 units | 1 search + 1 channel lookup |
| Full sync of 1 channel (500 videos, 5 playlists) | ~25 units | 1 metadata + 10 upload pages + 10 video batches + 1 playlist list + ~3 playlist pages |
| Incremental sync of 1 channel (2 new videos) | ~3 units | 1 metadata (batched) + 1 upload page + 1 video batch |
| Batch sync of 10 channels (incremental) | ~20–30 units | 1 batch metadata + per-channel incremental |
| Sync 1 monitored playlist (100 videos) | ~6 units | 2 item pages + 2 video batches + cache hits |

## Quota Optimization Strategies

### 1. Batched API Calls

The Client layer automatically batches IDs into groups of 50 for:
- **Channel metadata** (`get_channels_batch/1`): 10 channels → 1 API call instead of 10
- **Video details** (`fetch_videos_in_batches/1`): 200 videos → 4 API calls instead of 200
- **Playlist metadata** (`get_playlists_batch/1`): 50 playlists → 1 API call

The `BatchSyncWorker` uses `batch_refresh_channel_metadata/1` to fetch all
monitored channel metadata in a single batched call before processing individual
channels.

### 2. Video Detail Cache

During a full channel sync, uploads are fetched first. The resulting video
details are cached in a `%{video_id => raw_api_data}` map and passed to the
subsequent playlist sync phase. Since most playlist videos are a subset of
uploads, this avoids re-fetching video details:

```
sync_channel_content
├── sync_uploads           → fetches video details, returns video_cache
└── sync_playlists         → receives video_cache, only fetches uncached videos
```

**Example savings:** Channel with 500 videos across 5 playlists:
- Without cache: ~60 video detail API calls
- With cache: ~12 calls (uploads only) — 80% reduction

### 3. Incremental Sync (Early Termination)

For scheduled batch syncs, Ytdarr uses incremental fetching that stops
pagination once it encounters items older than the last sync time:

- **Uploads:** `check_uploads_for_new_videos/2` fetches playlist items page by
  page, stopping when `videoPublishedAt` is older than `since_datetime`. YouTube
  returns uploads in reverse chronological order, making this reliable.

- **Monitored playlists:** `check_playlist_for_new_videos/3` uses the same
  strategy. The `last_checked_at` timestamp on the playlist record provides the
  cutoff.

**Example savings:** Channel with 1,000 videos, 5 new since last sync:
- Full sync: ~20+ API calls
- Incremental: 1–2 API calls

### 4. Pre-flight Quota Checks

Before starting sync operations, workers estimate the total cost and check the
remaining budget:

- **BatchSyncWorker:** Estimates cost for all monitored channels and playlists
  via `QuotaTracker.estimate_batch_cost/2`. If insufficient, logs a warning and
  skips the run (the next scheduled run will retry).

- **SyncWorker:** Estimates cost for a single channel/playlist sync. If
  insufficient, uses Oban's `{:snooze, seconds}` to defer until the quota resets
  at midnight PT.

- **Search:** `Client.search_channels/1` checks `can_afford?(:search)` before
  executing. Returns `{:error, :quota_insufficient}` if the budget can't cover
  the 100-unit search cost.

### 5. Conditional Image Downloads

Channel avatar and banner images are downloaded using ETag-based conditional
requests (`If-None-Match`). When the remote image hasn't changed, the server
returns `304 Not Modified` and no bandwidth or processing is used. This is a
zero-cost optimization since image downloads don't consume YouTube API quota
(they're served from `yt3.ggpht.com`).

## Sync Flows

### Full Channel Sync

Triggered by user action or first sync. Fetches all data from scratch:

```
sync_channel_content(channel_id)
├── 1. sync_channel_metadata    → 1 API call (channel details)
├── 2. refresh_channel_images   → 0 API calls (ETag-based HTTP)
├── 3. sync_uploads             → N API calls (pagination + video batches)
│   └── Returns video_cache
├── 4. list_channel_playlists   → 1 API call
└── 5. per playlist:
    └── fetch_and_link_videos   → M API calls (uses video_cache)
```

### Incremental Batch Sync

Triggered on schedule. Only fetches new content since last check:

```
BatchSyncWorker.perform()
├── Pre-flight quota check
├── batch_refresh_metadata      → 1 API call per 50 channels
├── per channel (incremental):
│   ├── apply_batched_metadata  → 0 API calls (uses pre-fetched data)
│   └── check_uploads_new       → 1-2 API calls (early termination)
└── per monitored playlist (incremental):
    └── check_playlist_new      → 1-2 API calls (early termination)
```

### User-Initiated Sync

Triggered via UI "Sync Now" button:

```
SyncWorker.perform()
├── Pre-flight quota check
└── sync_channel_content()      → Full sync (same as above)
    OR sync_playlist_content()  → Full playlist sync
```

## QuotaTracker

The `QuotaTracker` GenServer maintains a running count of API units consumed.

### State Management

- **Persistence:** Usage is saved to the database (`AppSetting` resource) and
  restored on startup. This survives application restarts.
- **Reset:** The counter resets at midnight Pacific Time automatically.
- **Thresholds:** Warning at 80% usage, critical at 95%.

### Key Functions

| Function | Description |
|----------|-------------|
| `record_usage(type, count \\ 1)` | Records `count` operations of `type` (:read, :search, :write) |
| `get_usage()` | Returns `%{used, limit, remaining, percentage}` |
| `can_afford?(type, count \\ 1)` | Returns `true` if remaining budget covers the cost |
| `estimate_batch_cost(operation, count)` | Estimates cost for `:channel_sync` or `:playlist_sync` operations |
| `get_cost(type)` | Returns the unit cost for an operation type |

### Monitoring

The quota tracker's current state can be queried at any time:

```elixir
QuotaTracker.get_usage()
# => %{used: 450, limit: 10000, remaining: 9550, percentage: 4.5}
```

## Troubleshooting

### "Insufficient quota" warnings in logs

The pre-flight checks are preventing sync operations to preserve remaining
quota. This typically happens near the end of the day (PT timezone). Actions:

1. Check current usage: `QuotaTracker.get_usage()`
2. Wait for midnight PT reset
3. Consider reducing sync frequency in Settings → YouTube → Sync Interval

### Search returns `{:error, :quota_insufficient}`

Search operations cost 100 units each. If you're near the daily limit, search
is blocked to preserve quota for sync operations. Wait for the daily reset.

### High quota usage from full syncs

First-time channel syncs and forced full syncs are the most expensive
operations. Tips:

- Add channels during off-peak hours
- Avoid "Force Full Sync" unless necessary — incremental sync is much cheaper
- Monitor the quota tracker after adding channels with many videos

### API key not working

Verify your API key:
1. Check the YouTube tab in Settings
2. Ensure the key has YouTube Data API v3 enabled in Google Cloud Console
3. Check for IP restrictions on the API key that may block your server
