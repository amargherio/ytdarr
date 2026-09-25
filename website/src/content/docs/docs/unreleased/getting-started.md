---
title: Get started
description: Run Ytdarr locally, configure YouTube access and storage, and manually queue a first video.
sidebar:
  order: 2
---

Use this path to prove that Ytdarr can discover metadata and write media. It starts a source checkout; use [Docker Compose](../installation/docker-compose/) for a container deployment.

> **Trusted network required:** Ytdarr's management routes are not protected by the generated sign-in/register/reset screens. Keep this application on a trusted LAN or VPN, or put it behind an externally authenticated TLS proxy. See [security](../operations/security/).

## Prerequisites

Install the Elixir and Erlang versions in `.tool-versions`, plus `yt-dlp` and `ffmpeg` on `PATH`. Obtain a YouTube Data API v3 key, and choose a writable local directory for media. Only download material you have the right or permission to store.

## Start the application

1. Clone the repository and prepare its development dependencies and database:

   ```sh
   git clone https://github.com/amargherio/ytdarr.git
   cd ytdarr
   mix setup
   mix phx.server
   ```

2. Open `http://localhost:4000/settings`.
3. Save the API key in the YouTube settings and add an existing writable media root.

The server can start without an API key, but channel discovery, metadata sync, and other YouTube work cannot proceed until it has a valid key. If saving or testing the key fails, follow [YouTube API key and quota](../guides/youtube-api/).

## Add, sync, and download one video

1. Open **Channels → Add Channel** (`/channels/add`)—not the dashboard's `/channels/new` link.
2. Enter a direct channel URL, handle, or ID, select the desired add/sync/monitor choices, and add it. Direct add is the predictable option when those choices matter.
3. Open the channel detail page and run a metadata refresh or sync. Confirm videos appear.
4. Select one video and queue its download. Metadata monitoring and a sync do **not** automatically queue downloads.
5. Watch its status at [Downloads and queue](../guides/downloads-and-queue/), then point a TV-library view in Jellyfin, Plex, or Emby at the media root.

Expected result: the video progresses from an available item through the queue and is written into the channel's season directory with a generated NFO file. If yt-dlp, ffmpeg, media permissions, or the API key are unavailable, use [troubleshooting](../operations/troubleshooting/) rather than repeatedly queueing the same item.