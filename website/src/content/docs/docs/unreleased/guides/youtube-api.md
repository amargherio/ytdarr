---
title: YouTube API key and quota
description: Create, save, restrict, and diagnose the YouTube Data API v3 key used for Ytdarr metadata work.
sidebar:
  order: 1
---

Ytdarr needs a Google server API key to search YouTube and synchronize channel, playlist, and video metadata. It can start without one, but YouTube operations cannot work until a valid key is available.

## Create and restrict a key

1. In Google Cloud Console, create or select a project.
2. In **APIs & Services → Library**, enable **YouTube Data API v3**.
3. In **Credentials**, create an API key for server use.
4. Restrict it to the YouTube Data API v3 and restrict requests appropriately for the server's stable egress IP or network arrangement. Browser-referrer restrictions are not a substitute for a server key.
5. Record its quota use in Google Cloud Console.

## Save it in Ytdarr

Open **Settings**, save the key in the YouTube section, and use the page's test action. A direct `YTDARR_YOUTUBE_API_KEY` environment value overrides the stored value while it remains set. `YTDARR_YOUTUBE_API_KEY_FILE` can bootstrap an empty database from a read-only secret file; it does not replace an already stored key. Set only one form of each direct/file pair. See [environment reference](../../reference/environment/) for exact startup handling.

Expected result: direct channel resolution and metadata synchronization can begin. A missing, invalid, restricted, or exhausted key produces a visible failure rather than downloaded media.

## Interpret quota failures

Google allocates quota according to its own policy (commonly 10,000 units daily); requests such as search cost more than simple metadata lookups. Ytdarr records a fixed UTC-8/08:00 UTC accounting day for its own tracker, which is not daylight-saving-aware and is not proof of the provider's live reset. Check the provider console for the authoritative allocation and reset.

For `quota_insufficient` or exhaustion, wait for the provider reset or reduce unnecessary searches and sync frequency. For invalid/restricted-key failures, verify the API is enabled, the exact key was saved, and its server restriction permits this host. Do not expose the key in screenshots, support posts, backups, or a browser-visible proxy.