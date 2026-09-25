---
title: Backup and upgrades
description: Back up persistent Ytdarr state consistently and upgrade or roll back containers and native releases safely.
sidebar:
  order: 2
---

Back up application state before every upgrade. SQLite may use `-wal` and `-shm` sidecars, so copying only the database file is not a complete backup.

## Make a consistent backup

1. Stop the container or native service.
2. Copy the complete persistent `/data` volume (or the native state root), including SQLite sidecars and the environment-file location under your secret-handling policy.
3. Back up downloaded media separately; it is not necessarily inside `/data`.
4. Record the exact app image or native release version with the backup.

Restore the database and its matching app version together, then start the service and wait for `/health/ready`. Do not restore a live SQLite copy into a running service.

## Upgrade containers

Use an immutable exact release tag when one exists; moving minor and `latest` tags are not equivalent to a recorded version. The Unreleased documentation path is a local build, not a promise of a registry image. Stop and back up first, then update the selected image or rebuild, start it, and verify readiness and logs. See [Docker Compose](../../installation/docker-compose/) or [Podman Quadlet](../../installation/podman/).

## Upgrade native releases

`just deploy` builds an archive, verifies its checksum on the host, stops the service, makes a SQLite backup, migrates, updates the active symlink, starts, and waits for readiness. A migration or readiness failure automatically restores the preceding release and database. The default retention is three releases and three backups; `YTDARR_RELEASE_RETENTION` changes that retention.

To make an explicit rollback, run `just rollback server.example.com VERSION deployer` with a retained version. Native activation accepts prerelease suffixes, which does not make them stable publishing artifacts.

> **Repeat native secret repair:** after every provisioning or deployment attempt, including a failed activation, immediately set the deployed environment file to `root:ytdarr` and mode `0640`, then verify `stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env` reports `640 root:ytdarr`. Use configured helper overrides where applicable. The supplied helpers can otherwise expose it to other local users.