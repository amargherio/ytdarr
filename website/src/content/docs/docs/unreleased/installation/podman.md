---
title: Podman Quadlet installation
description: Build Ytdarr locally with Podman or operate a tagged release through a systemd Quadlet.
sidebar:
  order: 2
---

For this Unreleased version, build and run the exact local image named by `VERSION`; it currently resolves to `localhost/ytdarr:0.1.1-2`. Do not substitute an invented GHCR image or a moving registry tag. In a released documentation version, use the exact release tag shown in that page's version notice.

## Build and install a local Quadlet

1. Build the local linux/amd64 image from the current `VERSION` with a published builder tag:

   ```sh
   version="$(tr -d '[:space:]' < VERSION)"
   podman build --platform linux/amd64 -f deploy/Dockerfile \
     --build-arg VERSION="$version" \
     --build-arg BUILDER_IMAGE=docker.io/hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim \
     -t "localhost/ytdarr:$version" .
   ```

   The Dockerfile's default `hexpm/elixir:1.19.5-erlang-29-debian-bookworm-20260623-slim` tag is not published, so `just container-build` currently fails without a builder override. The explicit compatible builder above built a local image and passed an isolated container `/health/ready` check. It does not change `.tool-versions` for native/source builds.

2. Create a local Quadlet variation. It retains the supplied volumes, health check, and SELinux `:Z` mount, but changes `Image=` to the image built from `VERSION` and removes registry auto-update:

   ```sh
   version="$(tr -d '[:space:]' < VERSION)"
   temp_quadlet="$(mktemp)"
   sed -e "s|^Image=.*|Image=localhost/ytdarr:${version}|" \
       -e '/^AutoUpdate=registry$/d' \
       deploy/ytdarr.container > "$temp_quadlet"
   sudo install -d -m 0755 /etc/containers/systemd
   sudo install -m 0644 deploy/ytdarr-data.volume /etc/containers/systemd/ytdarr-data.volume
   sudo install -m 0644 "$temp_quadlet" /etc/containers/systemd/ytdarr.container
   rm "$temp_quadlet"
   ```

3. Generate the environment file and create the bind-mounted media directory:

   ```sh
   just generate-env /tmp/ytdarr.env localhost container 4000
   sudo install -d -m 0750 /etc/ytdarr
   sudo install -m 0640 /tmp/ytdarr.env /etc/ytdarr/ytdarr.env
   rm /tmp/ytdarr.env
   sudo install -d -o 10001 -g 10001 /srv/ytdarr/downloads
   ```

   Replace `localhost` with the trusted-network host name before exposing the service. Keep `/etc/ytdarr/ytdarr.env` private. The Quadlet keeps SQLite in the persistent `ytdarr-data.volume`, mounts `/srv/ytdarr/downloads` at `/downloads:Z`, and checks `/health/ready` on port 4000.

4. Start and inspect it with systemd:

   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable --now ytdarr.service
   sudo systemctl status ytdarr.service
   curl --fail http://127.0.0.1:4000/health/ready
   ```

Expected result: the service is active and the readiness request succeeds. Stop it with `sudo systemctl stop ytdarr.service`. If Podman reports a label or permission failure, recheck the `:Z` mount and that UID/GID `10001` can write the host directory.

## Released images and updates

For a real release, replace the local variation's `Image=` with that release's exact GHCR tag and use the supplied `AutoUpdate=registry` convention only when that release's update policy calls for it. A local Unreleased image must never enable registry auto-update. Back up persistent state before changing images; see [backup and upgrades](../../operations/backup-and-upgrades/).