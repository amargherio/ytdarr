---
title: Security and network exposure
description: Keep Ytdarr management, secrets, LiveView connections, and media filesystem access on a trusted boundary.
sidebar:
  order: 1
---

Ytdarr is intended for a trusted network. Keep it on a LAN or VPN, or put it behind an externally authenticated TLS reverse proxy. TLS encrypts traffic; it does **not** authorize a user.

## Protect the management surface

`/settings`, `/channels`, `/queue`, and `/oban` are not access-controlled merely because generated sign-in, registration, and reset routes exist. Do not expose them directly to the public Internet or present account creation as an access-control step. Put the application behind a VPN or proxy that requires authentication before traffic reaches Ytdarr.

A Phoenix LiveView session also requires WebSocket proxying. Set `PHX_HOST` to the public host and configure `ALLOWED_HOSTS` as the allowed WebSocket-origin list; it is not application authorization. Preserve the proxy's WebSocket upgrade headers and test a real interactive page after changes. See [environment reference](../../reference/environment/) for exact startup handling.

## Protect secrets and storage

Session data is signed, not encrypted. Keep signing secrets, the YouTube API key, SQLite `/data`, and backups private. UI masking of an API key is not database encryption. Restrict backups and mount secret files read-only where possible.

> **Native-helper limitation:** the supplied native provisioning and activation helpers can make the environment-file directory world-readable and install the secret file as `0644`. On a shared or untrusted multi-user host, use a container route instead. On a trusted dedicated host, immediately after **every** provisioning or deployment attempt—even a failed one—run `sudo chown root:ytdarr /etc/ytdarr/ytdarr.env` and `sudo chmod 0640 /etc/ytdarr/ytdarr.env`, then verify `stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env` returns `640 root:ytdarr`. Use your configured path and group if overridden.

## Limit filesystem exposure

The import browser can see files accessible to the service process only within `YTDARR_IMPORT_ROOTS` (empty by default). Give it dedicated import-only directories rather than the entire managed `/downloads` tree; already-managed media and same-stem companions are rejected as sources. Keep untrusted local writers out of these directories: validation of pathnames and symlinks is not atomic with the later filesystem operations. Avoid mounting unrelated private directories. Use a shared media group deliberately, protect the SQLite volume and backup copies, and revoke old API keys if they appear in logs or a copied environment file.