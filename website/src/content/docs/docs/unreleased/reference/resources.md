---
title: Media and download resources
sidebar:
  order: 4
description: Configure media roots, filesystem permissions, quality profiles, and yt-dlp parameter sets.
---

Resources are records managed in **Settings**, not environment variables. They validate against the host or container filesystem seen by the Ytdarr process. For related key/value controls, see [Settings](../settings/).

## Media root folders

A media-root record has the following fields:

<dl>
  <dt><code>path</code></dt><dd>Required, unique, nonblank absolute path. It must already exist, be a directory, and be writable by the Ytdarr process.</dd>
  <dt><code>purpose</code></dt><dd>Required string, default <code>videos</code>. Allowed values: <code>videos</code>, <code>music</code>, or <code>podcasts</code>.</dd>
  <dt><code>active</code></dt><dd>Required boolean, default <code>true</code>. The last active root cannot be disabled or deleted.</dd>
</dl>

When no active root exists, Ytdarr falls back to `/downloads` for newly derived channel paths. Multiple active roots are permitted, but there is **no ordering guarantee** among them; do not use `purpose` to expect content routing. Editing a root does not relocate saved channel paths or existing files.

### Add a root safely

1. Create the directory in the same host or container namespace as Ytdarr and grant the service process write access.
2. In **Settings → Media Management**, add its absolute path, choose a purpose, and leave it active.
3. Confirm that the root health check is healthy. If validation reports “not found,” “not a directory,” or “not writable,” correct the path or host permissions rather than entering a browser-local path.
4. Treat a root change as future placement only; move existing media with an operator-managed migration if required.

## Media permission policy

The media settings form manages three runtime keys:

- **`media.owner_group`**, default `ytdarr`: an existing POSIX group containing the service process; new media writes use it as their group.
- **`media.file_mode`**, default `0644`: three octal digits, optionally prefixed with `0`; new regular-file writes use it.
- **`media.directory_mode`**, default `0755`: three octal digits, optionally prefixed with `0`; new directory writes use it.

A system-group change is not visible to an already-running service process: add the service user to the group, then restart Ytdarr before saving/retrying. The policy applies group and modes to regular files and directories; it does not silently grant access through an incompatible mount.

**Apply to existing media** queues a `media_permissions` job that snapshots the selected group ID and modes at enqueue time. It traverses all configured roots, skips symbolic links rather than following them, and is best-effort: correct the reported paths and rerun if failures remain. It has one attempt, so a failed job is not retried automatically.

## Quality profiles

A quality profile records these fields:

<dl>
  <dt><code>name</code></dt><dd>Required, unique, nonblank string.</dd>
  <dt><code>max_height</code></dt><dd>Optional positive integer, in pixels.</dd>
  <dt><code>max_bitrate_kbps</code></dt><dd>Optional positive integer, in kbps.</dd>
  <dt><code>preferred_codecs</code></dt><dd>String array, default <code>[]</code>; ordered preference list.</dd>
  <dt><code>allow_hdr</code></dt><dd>Boolean, default <code>true</code>.</dd>
  <dt><code>format_selector</code></dt><dd>Optional string intended as an advanced yt-dlp format selector.</dd>
  <dt><code>is_default</code></dt><dd>Boolean, default <code>false</code>. Selecting a default clears the default flag from other profiles. A default profile cannot be deleted until a different profile is made default.</dd>
</dl>

> **Stored only:** every quality-profile preference is currently stored but not consumed by the downloader. Do not use a profile to promise a resolution, bitrate, codec, HDR, or format selection.

## yt-dlp parameter sets

A parameter-set record has these fields:

<dl>
  <dt><code>name</code></dt><dd>Required, unique, nonblank string.</dd>
  <dt><code>format</code></dt><dd>Optional yt-dlp format string.</dd>
  <dt><code>extra_args</code></dt><dd>Optional string of additional yt-dlp arguments.</dd>
  <dt><code>rate_limit_kbps</code></dt><dd>Optional positive integer. <strong>Stored only.</strong></dd>
  <dt><code>concurrency</code></dt><dd>Optional positive integer. <strong>Stored only.</strong> It does not change the Oban downloader queue.</dd>
  <dt><code>is_default</code></dt><dd>Boolean, default <code>false</code>. Selecting a default clears other defaults. A default set cannot be deleted until another set is made default.</dd>
</dl>

At worker execution, the downloader reads the resource marked default—so its `format` and `extra_args` affect jobs that were already queued as well as later jobs. No default set means only the base arguments run. `extra_args` is split on whitespace, **not** shell quoting; do not put a quoted argument containing spaces there. Only default `format` and `extra_args` are applied. `rate_limit_kbps`, per-set `concurrency`, and `yt_dlp.default_param_set_name` do not configure the effective downloader.

Every download starts with these exact base arguments:

```text
--embed-chapters
--embed-thumbnail
--embed-metadata
--embed-subs
--write-auto-subs
--merge-output-format mp4
--mtime
```

When the default set has a nonempty `format`, Ytdarr appends `-f <format>`. When it has nonempty `extra_args`, Ytdarr appends each whitespace-separated token. It then adds its own progress and output arguments. See [Queues and quota](../queues-and-quota/#worker-queues) for global worker capacity.

### Cookie files and advanced arguments

There is no dedicated cookie setting. If an operator must use yt-dlp cookie-file options, add them as advanced `extra_args`, mount the cookie file read-only where the service can read it, and treat it as sensitive operational data. Keep such files out of SQLite, browser-visible screenshots, source control, and backups that are not protected appropriately.

## Recovery paths

- **Root validation fails:** verify the path inside the running container/service namespace and the service account's write access.
- **New files have the wrong group or mode:** check the saved policy, group membership, and a service restart after membership changes. Use **Apply to existing media** only after the policy validates.
- **A profile has no effect:** this is expected; all profile preferences are stored only.
- **A rate limit or per-set concurrency has no effect:** this is expected; use the code/deployment queue capacity described in [Queues and quota](../queues-and-quota/) rather than a stored parameter-set field.
- **yt-dlp rejects custom arguments:** remove or simplify the whitespace-split `extra_args`, then inspect the worker/log output. Do not assume shell-style quote parsing.
