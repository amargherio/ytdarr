---
title: Ytdarr documentation
description: Task-oriented documentation for installing, operating, configuring, and contributing to Ytdarr.
sidebar:
  order: 1
---

Ytdarr is a self-hosted YouTube channel monitor and video downloader for Jellyfin, Plex, and Emby. A **channel** is a show, a channel upload year is a season, and a downloaded **video** is an episode. Ytdarr uses Phoenix LiveView and SQLite for the application, Oban for background jobs, the YouTube Data API for metadata, and yt-dlp for files.

These are **Unreleased** development-build docs: no stable release is published. When releases exist, the site retains the newest stable patch from each minor line. Select the version that matches the code you run before following a command.

## Start with a task

- [Set up a first channel and download](./getting-started/)
- [Build and run with Docker Compose](./installation/docker-compose/)
- [Create and restrict a YouTube API key](./guides/youtube-api/)
- [Keep the management interface on a trusted network](./operations/security/)
- [Find every runtime and stored setting](./reference/)

## Documentation directory

### Start here

- [Overview](./)
- [Get started](./getting-started/)

### Installation

- [Docker Compose](./installation/docker-compose/)
- [Podman Quadlet](./installation/podman/)
- [Native systemd release](./installation/native/)

### Guides

- [YouTube API key and quota](./guides/youtube-api/)
- [Channels and playlists](./guides/channels-and-playlists/)
- [Downloads and queue](./guides/downloads-and-queue/)
- [Import existing media](./guides/importing-existing-media/)
- [Media library organization](./guides/media-library/)

### Operations

- [Security and network exposure](./operations/security/)
- [Backup and upgrades](./operations/backup-and-upgrades/)
- [Troubleshooting](./operations/troubleshooting/)

### Reference

- [Configuration overview](./reference/)
- [Environment](./reference/environment/)
- [Stored settings](./reference/settings/)
- [Media roots, profiles, and parameter sets](./reference/resources/)
- [Queues and quota](./reference/queues-and-quota/)

### Development

- [Development setup](./development/)
- [Architecture](./development/architecture/)
- [Contributing](./development/contributing/)
- [Website authoring](./development/website/)

The directory above is complete so it remains usable without JavaScript or the documentation sidebar.