---
title: Troubleshooting
description: Diagnose Ytdarr startup, API, sync, download, media, import, and proxy failures without destructive guesses.
sidebar:
  order: 3
---

Start with service logs and the health endpoints: `/health/live` shows the process is alive; `/health/ready` is the readiness check. Containers use `docker compose -f deploy/compose.yaml logs`; native installs use `journalctl -u ytdarr`. `/oban` exposes job diagnostics.

## Common symptoms

- **Metadata search or sync fails:** Check that the API key is present, valid, enabled and permitted by its restrictions. Test a valid key, inspect provider quota, and follow the [YouTube API guide](../../guides/youtube-api/).
- **Quota exhausted:** Compare the provider console with Ytdarr's tracker. Wait for the provider reset and reduce unnecessary searches or syncs.
- **Metadata looks stale:** Check monitoring state, scheduled sync job and quota. Run a refresh, then inspect its job rather than repeatedly adding the channel.
- **Queued or stalled download:** Check `/queue`, `/oban`, and yt-dlp/ffmpeg availability. Read the job error and correct the cause before re-queuing.
- **File missing:** Check the media root and service group. Restore the file or correct permissions, then read the single-video recovery message.
- **Import fails or conflicts:** Check source and destination accessibility and recovery state. Do not overwrite a destination; correct the cause, then use **Retry recovery** or **Retry cleanup**.
- **WebSocket page disconnects:** Check reverse-proxy upgrade handling, `PHX_HOST` and `ALLOWED_HOSTS`. Correct origin/proxy configuration; `ALLOWED_HOSTS` is not authorization.
- **Startup exits parsing a value:** Check `PORT` and `POOL_SIZE`. Both require valid integers; malformed values fail runtime parsing.
- **Startup rejects a secret file:** Check path, permissions and nonempty contents. The direct and file forms are exclusive.
- **Readiness stays unhealthy:** Check persistent storage, database and logs. Preserve data and correct the underlying fault rather than deleting `/data`.

## Product limitations to account for

Quality profiles, naming, move strategy, orphan cleanup, and some parameter-set controls are stored settings rather than proven downloader behavior. Downloads are manually selected; monitoring does not queue uploads. The app assumes trusted-network management access and currently supports YouTube.

The channel-detail **Delete Files** controls are unimplemented. The channel-list **Remove → Delete downloaded files** action does work and recursively removes the stored channel directory, so it is destructive—not a harmless workaround.

Development-only `/admin`, `/dev/dashboard`, and `/dev/mailbox` routes are not the production application surface. Do not expose any route publicly; see [security](../security/).