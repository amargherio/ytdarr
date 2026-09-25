---
title: Queues and quota
sidebar:
  order: 5
description: Operate Ytdarr background worker capacity, scheduled metadata sync, and YouTube API quota bookkeeping.
---

Ytdarr uses Oban for background work. Queue concurrency is code/deployment configuration, not a browser Settings control and not a yt-dlp parameter-set field. Open `/oban` on a trusted network to inspect jobs; it is not a pause, cancel, or reorder console.

## Worker queues

- **`default`: 10 workers.** General-purpose queue; retries depend on the worker.
- **`video_downloader`: 2 in base/development, 5 in production.** Runs yt-dlp downloads; uses Oban's worker default for retries, not a universal three-attempt setting.
- **`video_importer`: 2 workers.** Imports existing media; one attempt.
- **`sync_worker`: 5 workers.** Runs user-triggered channel or playlist metadata sync; three attempts.
- **`batch_sync`: 1 worker.** Runs scheduled sync of monitored content; three attempts and a five-minute uniqueness window.
- **`media_permissions`: 1 worker.** Applies captured group and mode policy to configured roots; one attempt.

The base configuration supplies `default: 10`, `video_downloader: 2`, `video_importer: 2`, `sync_worker: 5`, `batch_sync: 1`, and `media_permissions: 1`. Production changes downloader capacity to 5; development leaves it at 2. These values are not environment variables or Settings UI fields.

### What an operator can expect

- A queued download waits for `video_downloader` capacity and then invokes yt-dlp with the effective default parameter-set `format`/`extra_args` and the base flags listed in [Resources](../resources/#yt-dlp-parameter-sets).
- Metadata monitoring creates/updates channel and playlist metadata; it does **not** automatically queue downloads.
- `/queue` shows download status and offers refresh, while `/oban` exposes job diagnostics. Neither is a complete job-control surface.
- The capacity values bound concurrent workers, not an exact guarantee of immediate start order.

## Scheduling metadata sync

At application boot, Ytdarr queues the first batch-sync job for **120 seconds** later. After each batch run, it schedules its successor according to `sync_interval_minutes`, default 60 minutes. A change to that setting takes effect when the next batch job schedules its successor; it does not alter a job already waiting. See [Settings](../settings/#automatic-metadata-sync).

Batch sync operates on monitored channels and playlists. It estimates quota before work, batches metadata calls where possible, and performs incremental checks using `last_checked_at` where applicable. A manual single-content sync uses `sync_worker`, not the batch scheduler.

If an automatic or manual sync cannot afford its estimated YouTube quota, it is deferred until the tracker’s calculated reset. Check the API key and quota rather than increasing worker concurrency to resolve that condition.

## YouTube API quota

The YouTube Data API default project budget is **10,000 units per day**. Ytdarr’s tracker charges one unit for a read and 100 units for a search. These are tracker costs; Google provider policy and actual endpoint costs remain authoritative.

The tracker persists usage in SQLite, so use survives restarts. It has the following internal records:

<dl>
  <dt><code>youtube.daily_quota_limit</code></dt><dd>Advanced database setting. If absent, the tracker uses 10,000. It is read when the tracker starts and when its day rolls over; it is not a catalog/UI tuning control.</dd>
  <dt><code>youtube.quota_used_today</code></dt><dd>Internal persisted usage bookkeeping, not an operator configuration control.</dd>
  <dt><code>youtube.quota_reset_date</code></dt><dd>Internal persisted bookkeeping date, not an operator configuration control.</dd>
</dl>

### Reset-time distinction

Google documents its default quota reset in Pacific Time. Ytdarr’s bookkeeping is deliberately simpler: it calculates the day as UTC−8 and reports the next reset as 08:00 UTC, checking for rollover hourly. It is **not DST-aware**. Treat the provider console and provider enforcement as the source of truth; the application counter is an operational guard, not a replacement for provider quota visibility.

## Safe operations and recovery

1. If YouTube work is blocked at startup or during sync, verify the effective key in [Settings](../settings/), including a direct environment override or secret-file bootstrap from [Runtime environment](../environment/#youtube-credential-bootstrap).

2. If quota is exhausted, wait for the provider reset and review Google Cloud quota; do not reset internal bookkeeping to manufacture provider capacity.
3. If downloads remain pending, inspect `video_downloader` work in `/oban`, yt-dlp availability, filesystem health, and queue capacity. A stored `rate_limit_kbps` or parameter-set `concurrency` will not change worker capacity.
4. If a batch cycle seems slow, confirm monitored content and the scheduled job. Changing `sync_interval_minutes` affects only the next self-scheduled cycle.
5. If permission normalization reports failures, correct filesystem ownership/modes and queue **Apply to existing media** again; that worker has one attempt and skips symlinks.
