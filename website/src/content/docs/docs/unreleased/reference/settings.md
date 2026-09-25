---
title: Settings catalog
sidebar:
  order: 3
description: Understand the nine browser-managed application settings, their defaults, validation, and real runtime effects.
---

Open **Settings** at `/settings` to manage database-backed application settings. This page covers the current catalog, not every value visible in the System panel. Runtime environment and deployment controls are documented in [Runtime environment](../environment/); resource records are documented in [Resources](../resources/).

A catalog default is a read fallback, not a promise that a SQLite row has been seeded. “Stored only” means the value is saved and shown, but current runtime code does not consume it. Do not rely on such values to change downloads or clean files.
For every catalog entry except the API-key override described below, lookup uses the saved database value and otherwise its catalog default; none has an environment override. No entry other than the API key is secret.

## YouTube

### `youtube.primary_api_key`

<dl>
  <dt>Type, default, and secrecy</dt><dd>String; unset by default; <strong>secret</strong>.</dd>
  <dt>Input and scope</dt><dd>A YouTube Data API v3 key, stored in SQLite when saved through Settings. The UI masks a configured value; masking does not encrypt the database.</dd>
  <dt>Precedence</dt><dd>A nonempty direct <code>YTDARR_YOUTUBE_API_KEY</code> takes precedence over the database at runtime. Its <code>_FILE</code> form can only bootstrap an empty database value. See [Runtime environment](../environment/#youtube-credential-bootstrap).</dd>
  <dt>Application timing</dt><dd>Runtime: the key is read for YouTube operations. Startup remains possible without it, but YouTube operations cannot work without valid credentials.</dd>
</dl>

Use the Settings test to make a minimal YouTube API request. It reports empty keys, invalid/restricted keys, exhausted quota, network failures, and unexpected HTTP responses without displaying the secret.

### `youtube.region`

<dl>
  <dt>Type and default</dt><dd>String; <code>US</code>.</dd>
  <dt>Precedence</dt><dd>Saved database value, otherwise the <code>US</code> catalog fallback; no environment override.</dd>
  <dt>Allowed input</dt><dd>The browser form requires exactly two ASCII letters.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; <strong>stored only</strong>. It is reserved for future region-aware requests and currently changes no YouTube request.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

## Media management

### `media.file_naming_template`

<dl>
  <dt>Type and default</dt><dd>String; <code>%(channel)s/%(title)s.%(ext)s</code>.</dd>
  <dt>Allowed input and precedence</dt><dd>Any string accepted by the setting form; saved database value, otherwise the displayed catalog fallback. No environment override.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; <strong>stored only</strong>. It is intended for a future configurable naming pipeline. Current downloads use the built-in canonical artifact naming.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

### `media.move_strategy`

<dl>
  <dt>Type and default</dt><dd>String; <code>hardlink</code>.</dd>
  <dt>Allowed input</dt><dd><code>hardlink</code>, <code>copy</code>, or <code>move</code>.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; <strong>stored only</strong>. Current downloads write directly to their destination rather than selecting one of these strategies.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

### `media.clean_orphans`

<dl>
  <dt>Type and default</dt><dd>Boolean; <code>true</code>.</dd>
  <dt>Allowed input and precedence</dt><dd>A boolean value; saved database value, otherwise <code>true</code>. No environment override.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; <strong>stored only</strong>. It does not enable automatic orphan cleanup.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

### `media.owner_group`

<dl>
  <dt>Type and default</dt><dd>String; <code>ytdarr</code>.</dd>
  <dt>Precedence</dt><dd>Saved database value, otherwise <code>ytdarr</code>; no environment override.</dd>
  <dt>Allowed input</dt><dd>A valid POSIX group that exists on the host and includes the running service process.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; runtime for new media writes. A changed OS group membership requires a service-process restart before validation can succeed.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

### `media.file_mode`

<dl>
  <dt>Type and default</dt><dd>String; <code>0644</code>.</dd>
  <dt>Precedence</dt><dd>Saved database value, otherwise <code>0644</code>; no environment override.</dd>
  <dt>Allowed input</dt><dd>Three octal digits, with an optional leading zero—for example <code>640</code> or <code>0640</code>.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; runtime for new regular-file writes.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

### `media.directory_mode`

<dl>
  <dt>Type and default</dt><dd>String; <code>0755</code>.</dd>
  <dt>Precedence</dt><dd>Saved database value, otherwise <code>0755</code>; no environment override.</dd>
  <dt>Allowed input</dt><dd>Three octal digits, with an optional leading zero—for example <code>750</code> or <code>0750</code>.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; runtime for newly created directories.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

New writes use the saved ownership/mode policy. Existing files do not change when you save. Use **Apply to existing media** to queue a normalization job; it captures the policy at enqueue time, skips symbolic links, and reports per-path failures. See [Resources](../resources/#media-permission-policy).

## Automatic metadata sync

### `sync_interval_minutes`

<dl>
  <dt>Type and default</dt><dd>Positive integer; <code>60</code> minutes.</dd>
  <dt>Precedence</dt><dd>Saved database value, otherwise <code>60</code>; no environment override.</dd>
  <dt>Allowed input</dt><dd>A whole number greater than zero.</dd>
  <dt>Scope and timing</dt><dd>SQLite application setting; applies when the current batch-sync job schedules its successor. Changing it does not rewrite a job that is already scheduled.</dd>
  <dt>Secret?</dt><dd>No.</dd>
</dl>

The first batch sync is queued 120 seconds after boot. Sync fetches metadata for monitored content; it does not automatically queue video downloads. Queue limits and retries are in [Queues and quota](../queues-and-quota/).

## What is not a catalog control

`youtube.daily_quota_limit` is an advanced database setting read by the quota tracker at startup/day rollover; it is not in the browser catalog. `youtube.quota_used_today` and `youtube.quota_reset_date` are internal bookkeeping, not tuning controls. `yt_dlp.default_param_set_name` appears in an aggregated settings view but is not the downloader's effective selection mechanism: the downloader reads the resource record marked default. Resource records themselves are documented in [Resources](../resources/).

## Safe change procedure

1. Read the setting's effect above before saving it; do not expect a **Stored only** control to change runtime behavior.
2. Save valid values in the matching Settings category. A section save is transactional: if any setting in that save fails, the section is not partially saved.
3. For ownership or mode changes, make the service account a member of the selected group, restart after any OS-group change, then optionally run **Apply to existing media**.
4. If the API-key UI cannot clear a key, check whether the direct environment override is active; change the deployment environment, not the database field.
