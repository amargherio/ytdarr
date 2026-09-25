---
title: Runtime environment
sidebar:
  order: 2
description: Configure production runtime variables, secret files, and deployment helpers without confusing them with Settings.
---

Runtime variables are read when the release starts. They are separate from the browser **Settings** records described in [Settings](../settings/). Keep the management interface on a trusted network; these variables do not add application authorization.

## Required production inputs

The production runtime requires the following values before it can start:

<dl>
  <dt><code>DATABASE_PATH</code></dt>
  <dd><strong>Required in production.</strong> SQLite database path. The runtime does not check that this path is absolute, but an absolute host path is the safe operator choice. The generated container environment uses <code>/data/ytdarr.db</code>; the generated native environment uses <code>/var/lib/ytdarr/ytdarr.db</code>.</dd>
  <dt><code>SECRET_KEY_BASE</code> or <code>SECRET_KEY_BASE_FILE</code></dt>
  <dd><strong>Required in production; secret.</strong> Cookie and endpoint secret material. Supply exactly one direct value or one readable file path.</dd>
  <dt><code>TOKEN_SIGNING_SECRET</code> or <code>TOKEN_SIGNING_SECRET_FILE</code></dt>
  <dd><strong>Required in production; secret.</strong> Token-signing material. Supply exactly one direct value or one readable file path.</dd>
</dl>

`Ytdarr.Env` trims a direct secret value or a secret-file's contents. A missing required value, a blank direct value, an empty secret file, an unreadable file, or a blank `*_FILE` path stops startup. Supplying both members of any direct/file pair is an error **even if one is blank**. Protect the environment file, the secret files, the SQLite database, and backups; masking a key in the interface is not database encryption.

## Listener and endpoint

<dl>
  <dt><code>PHX_SERVER</code></dt>
  <dd>Enables the Phoenix server whenever the variable is present. This is a presence check: <code>PHX_SERVER=false</code> still enables it. The container image sets it to <code>true</code>.</dd>
  <dt><code>PHX_HOST</code></dt>
  <dd>External hostname, default <code>example.com</code>. Production endpoint URLs are rendered as HTTPS on port 443.</dd>
  <dt><code>PORT</code></dt>
  <dd>Internal HTTP listener port, default <code>4000</code>. It is distinct from the public HTTPS port in the endpoint URL. It must parse as an integer; malformed input stops startup.</dd>
  <dt><code>ALLOWED_HOSTS</code></dt>
  <dd>Comma-separated WebSocket origin hosts. Whitespace around each item is trimmed and a missing <code>//</code> prefix is added. When unset it becomes <code>//PHX_HOST</code>. This is origin checking for LiveView WebSockets, not application authorization.</dd>
  <dt><code>POOL_SIZE</code></dt>
  <dd>SQLite repository pool size, default <code>10</code>. It must parse as an integer; malformed input stops startup. The generated deployment environment deliberately uses <code>5</code>.</dd>
  <dt><code>DNS_CLUSTER_QUERY</code></dt>
  <dd>Optional DNSCluster query. When absent, clustering is ignored.</dd>
  <dt><code>YTDARR_IMPORT_ROOTS</code></dt>
  <dd>Optional, non-secret comma-separated list of absolute directories visible to the service; default is empty, disabling import browsing. Whitespace is trimmed, repeated roots are removed, and a relative path stops startup. Set only trusted-writable, import-only staging paths, not the managed <code>/downloads</code> tree. A source or companion already recorded as another video's downloaded media is rejected. A directory must exist and be writable when browsing/importing; changes take effect after restart. Path checks reject pre-existing symlinks but are not atomic against another process changing directories concurrently. See <a href="../../guides/importing-existing-media/">Import existing media</a>.</dd>
</dl>

A Compose host-port mapping changes only the host side of `YTDARR_PORT:4000`; it does not change the container listener, the image's `PORT=4000`, or its readiness probe.

## YouTube credential bootstrap

<dl>
  <dt><code>YTDARR_YOUTUBE_API_KEY</code></dt>
  <dd>Optional secret. A nonempty direct value overrides the database key for runtime calls. It is also saved into an empty database at startup. If it remains present, editing the browser field cannot replace the effective value.</dd>
  <dt><code>YTDARR_YOUTUBE_API_KEY_FILE</code></dt>
  <dd>Optional secret-file path. Its trimmed contents can bootstrap <code>youtube.primary_api_key</code> only when the database key is empty. It does not rotate or override an already-stored key.</dd>
</dl>

The direct and file forms are exclusive. The startup loader evaluates the file form before it decides whether the database already contains a key, so an invalid file path or empty file can stop startup even when the database has a key. A YouTube key is optional for application startup but required for YouTube API discovery and metadata sync. An already-known video may be downloaded by yt-dlp without this API key; yt-dlp access is separate. See [Settings](../settings/) and [Queues and quota](../queues-and-quota/) for the stored key and quota behavior.

## Deployment helper variables

These names are consumed by deployment files or image builds, not by the running app's Settings UI.

### Compose and container helpers
`MIX_ENV`, the image `LANG`, `LANGUAGE`, and `LC_ALL` values, and the commented `TZ` example in `deploy/env.example` are build/tooling or operating-system context, not supported application settings. `RELEASE_NAME` is release-runtime metadata used by the application to decide whether to run migrations; it is not an operator tuning knob.
<dl>
  <dt><code>YTDARR_VERSION</code></dt><dd>Compose build argument for the image label; default <code>dev</code>.</dd>
  <dt><code>YTDARR_PORT</code></dt><dd>Host port published to the fixed container port 4000; default <code>4000</code>.</dd>
  <dt><code>YTDARR_DOWNLOADS_PATH</code></dt><dd>Host path bound to <code>/downloads</code>; default <code>./downloads</code>. It does not change any stored application root path.</dd>
  <dt><code>ELIXIR_VERSION</code>, <code>OTP_VERSION</code>, <code>DEBIAN_VERSION</code></dt><dd>Docker build inputs for the builder/runtime images.</dd>
  <dt><code>BUILDER_IMAGE</code>, <code>RUNNER_IMAGE</code></dt><dd>Docker base-image build inputs.</dd>
  <dt><code>YT_DLP_VERSION</code>, <code>YT_DLP_SHA256</code></dt><dd>Docker build inputs that select and verify yt-dlp. Read the current pins from <code>deploy/Dockerfile</code> rather than maintaining a second version list.</dd>
  <dt><code>VCS_REF</code>, <code>VERSION</code></dt><dd>OCI image-label build inputs.</dd>
</dl>

The current default `BUILDER_IMAGE` derived from `ELIXIR_VERSION=1.19.5`, `OTP_VERSION=29`, and `DEBIAN_VERSION=bookworm-20260623-slim` is not published. Current Unreleased container builds must override `BUILDER_IMAGE` with the tested published Elixir 1.20.4/OTP 29.1.1 Bookworm tag shown in [Docker Compose](../../installation/docker-compose/#build-and-start) and [Podman](../../installation/podman/#build-and-install-a-local-quadlet). This is an image-build input, not a change to the running app Settings or source tool versions.


### Native deployment helpers

The native scripts read these optional helper overrides:

<dl>
  <dt><code>YTDARR_APP_USER</code> / <code>YTDARR_APP_GROUP</code></dt><dd>Service account and POSIX group; defaults <code>ytdarr</code>.</dd>
  <dt><code>YTDARR_INSTALL_ROOT</code></dt><dd>Release installation root; default <code>/opt/ytdarr</code>.</dd>
  <dt><code>YTDARR_STATE_ROOT</code></dt><dd>State and backup root; default <code>/var/lib/ytdarr</code>.</dd>
  <dt><code>YTDARR_ENV_FILE</code></dt><dd>Installed environment-file path; default <code>/etc/ytdarr/ytdarr.env</code>.</dd>
  <dt><code>YTDARR_SERVICE_NAME</code></dt><dd>systemd service name; default <code>ytdarr</code>.</dd>
  <dt><code>YTDARR_RELEASE_RETENTION</code></dt><dd>Native activation retention count; default <code>3</code>.</dd>
</dl>

> **Native secret-file warning:** the current provisioning helper installs the environment file as mode 0644 and recursively makes its directory world-readable; activation repeats the widening. On a shared or untrusted multi-user host, prefer the container route. On a trusted dedicated host, immediately after **every** provisioning or deployment attempt—including a failed activation—run the following on the target host, substituting configured path/group overrides when used:
>
> ```sh
> sudo chown root:ytdarr /etc/ytdarr/ytdarr.env
> sudo chmod 0640 /etc/ytdarr/ytdarr.env
> stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env
> # 640 root:ytdarr
> ```

## Recovery checklist

1. For a production startup failure, first check a missing `DATABASE_PATH`, one of the two required signing secrets, malformed `PORT`/`POOL_SIZE`, or a direct/file secret conflict.
2. For a LiveView origin failure, align `PHX_HOST`, the proxy host, and comma-separated `ALLOWED_HOSTS`; do not treat this as an authentication configuration.
3. For YouTube failures after a successful boot, confirm a valid effective API key and check quota in [Queues and quota](../queues-and-quota/).
4. Use the deployment path appropriate to the server in [Docker Compose](../../installation/docker-compose/), [Podman](../../installation/podman/), or [native setup](../../installation/native/).
