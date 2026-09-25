---
title: Configuration reference
sidebar:
  order: 1
description: Find the exact Ytdarr runtime, Settings, media-resource, queue, and quota configuration behavior.
---

Use this reference when configuring a deployment or deciding whether a Settings control changes running behavior. It separates three layers that are easy to confuse:

1. **Runtime environment** configures the released process, listener, database, secrets, and deployment helpers.
2. **Settings** are SQLite-backed key/value records managed in the browser.
3. **Resources** are SQLite-backed media-root, profile, and yt-dlp parameter-set records.

A value marked **Stored only** is real persisted data, but current runtime code does not consume it. It is not a promise of a future download, naming, move, cleanup, quality, rate-limit, or concurrency effect.

## Start with the right page

- [Runtime environment](./environment/) — required production secrets, `PHX_SERVER`, database/listener values, YouTube bootstrap rules, Compose/image/native helper variables, and the native environment-file warning.
- [Settings catalog](./settings/) — every browser-managed catalog key, default, validation, precedence, secrecy, and application timing.
- [Media and download resources](./resources/) — media roots, permission policy, profiles, parameter sets, base yt-dlp flags, and cookie-file handling.
- [Queues and quota](./queues-and-quota/) — Oban capacity, batch scheduling, retry distinctions, and YouTube quota bookkeeping.

## Operator workflow

1. Set the required production environment: a database path and both signing secrets. Use either each direct secret variable or its corresponding `*_FILE`, never both.
2. Start Ytdarr, then add a writable media root visible to the service process.
3. Configure a YouTube Data API v3 key in **Settings**, or use the documented bootstrap/override route.
4. Review the effective ownership and mode policy before the first download. Ensure the service process belongs to its configured group.
5. Configure only controls whose actual effect matches the desired outcome; consult the resource and queue pages before assuming a stored value changes runtime behavior.

## Scope and safety

The Settings and diagnostics routes are operational surfaces, not access-control boundaries. Keep them on a trusted network or behind an externally authenticated proxy. Protect SQLite, backups, environment files, and any yt-dlp cookie file as sensitive operational data.

For installation procedures, choose [Docker Compose](../installation/docker-compose/), [Podman](../installation/podman/), or [native/source setup](../installation/native/). For a first end-to-end setup, start at [Get started](../getting-started/).
