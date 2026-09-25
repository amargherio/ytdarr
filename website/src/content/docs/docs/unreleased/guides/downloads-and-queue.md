---
title: Downloads and queue
description: Manually queue videos, read download states, and use the queue and Oban diagnostics safely.
sidebar:
  order: 3
---

Ytdarr discovers and monitors metadata automatically, but **you choose which videos download**. On a channel detail page, select a video and queue it, then use `/queue` to observe work.

## Read video states

An item may be **Available** (known but not queued), **Queued**, **Downloading**, **Downloaded**, or **Missing**; imports add their own in-progress and recovery states. Progress, speed, and ETA describe active work. The pending list provides an approximate order and workers have finite capacity, so it is not a promise of exact start time.

1. Queue one selected video from its channel detail page.
2. Open `/queue` and use **Refresh** to update the view.
3. Inspect `/oban` for jobs, queue pressure, and failures when work stalls.
4. Open the video or channel detail page for file-specific recovery messages.

`/queue` is a monitoring screen with Refresh. It is not a pause, cancel, reorder, retry, or bulk-repair console. Do not infer those controls from a job's presence.

## Blocked and missing media

If a video is blocked, unblock it only after correcting the underlying issue. For a downloaded file that is deleted or no longer reachable, use the single-video file action and the UI's recovery message; check writable roots, group membership, and yt-dlp/ffmpeg before retrying. See [troubleshooting](../../operations/troubleshooting/).

The channel-detail **Delete Files** controls for a channel, playlist, or all videos are unimplemented. The working channel-list **Remove → Delete downloaded files** action is instead destructive recursive deletion; it is not a queue cleanup button. Metadata monitoring never queues new uploads on its own.