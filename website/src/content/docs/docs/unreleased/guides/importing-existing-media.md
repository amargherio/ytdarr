---
title: Import existing media
description: Import one existing video file for a known Ytdarr video while preserving recoverable failures.
sidebar:
  order: 4
---

Import is for a file already accessible to the Ytdarr host or container and for a video Ytdarr already knows. It is not a browser upload or a bulk library scanner. Preserve a backup: a successful import consumes or moves source material.

Configure `YTDARR_IMPORT_ROOTS` with comma-separated absolute import-only directories and restart; when unset, browsing is disabled. For the stock Compose mount, create `deploy/downloads/.incoming` writable by UID/GID `10001` and use `YTDARR_IMPORT_ROOTS=/downloads/.incoming`, not the managed `/downloads` directory.

A dedicated bind mount outside the managed media root separates sources more reliably. Grant write access only to trusted local processes; a concurrent symlink swap by another writer can race pathname validation.

## Import one file

1. Open the known video's row and choose its import action.
2. Browse or filter the **host filesystem** visible to Ytdarr; select the source video.
3. Inspect the calculated destination and quality details.
4. Optionally choose matching subtitle/artwork sidecars, then confirm.
5. Observe progress and completion on the video row.

Supported video extensions are `mp4`, `mkv`, `webm`, `mov`, `m4v`, `avi`, `mpg`, `mpeg`, `ts`, `m2ts`, `wmv`, `flv`, and `ogv`. Sidecars may be `srt`, `vtt`, `ass`, `ssa`, `jpg`, `jpeg`, `png`, or `webp`. Ytdarr writes canonical NFO metadata; an old NFO is not trusted as the authoritative record.

## Resolve failures without data loss

A destination conflict does not overwrite an existing file. An already-managed video or its companions cannot be imported as a source for another video; place a separate, import-only copy in the staging directory instead. Correct the destination or source issue rather than forcing an overwrite. Changed/missing sources, unavailable permissions, and blocked or in-progress states can create recovery records. Use **Retry recovery** or **Retry cleanup** after fixing the cause; do not delete recovery records to make them disappear.

If a source disappears before processing, restore it or select the correct accessible file. If permissions fail, grant the service process access to both source and destination and retry. If cleanup is pending, let recovery finish before attempting another import. See [media library organization](../media-library/) for destination structure and [troubleshooting](../../operations/troubleshooting/) for host diagnostics.