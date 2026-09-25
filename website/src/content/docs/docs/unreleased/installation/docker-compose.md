---
title: Docker Compose installation
description: Build and run the Unreleased Ytdarr source with Docker Compose and persistent media storage.
sidebar:
  order: 1
---

Use this route for the current Unreleased source. For a released documentation version, check out the exact source tag named in its version notice and use that release's matching image or source—not `main`.

## Prerequisites

Install Docker with the Compose plugin. The initial local build needs the repository checkout; the container runs as UID/GID `10001`. Choose a trusted-network hostname and a host media directory whose ownership permits that identity to write.

## Build and start

1. Clone the repository and generate an ignored environment file with new signing secrets:

   ```sh
   git clone https://github.com/amargherio/ytdarr.git
   cd ytdarr
   just generate-env deploy/.env localhost container 4000
   ```

2. Prepare the host bind mount for the container user:

   ```sh
   mkdir -p deploy/downloads
   sudo chown 10001:10001 deploy/downloads
   ```

3. Build the local image with a published compatible builder, then start only that image:

   ```sh
   docker compose -f deploy/compose.yaml build \
     --build-arg BUILDER_IMAGE=docker.io/hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim
   docker compose -f deploy/compose.yaml up --no-build --pull never -d
   ```

   The Dockerfile's current default `hexpm/elixir:1.19.5-erlang-29-debian-bookworm-20260623-slim` does not exist in the registry. This explicit build argument selects an available Elixir 1.20.4/OTP 29.1.1 builder compatible with `mix.exs` (`~> 1.19`); the resulting local image started and passed `/health/ready` in an isolated Podman smoke run. It does not change the app's source-development `.tool-versions` or the published runtime image tag.

4. Follow startup and readiness:

   ```sh
   docker compose -f deploy/compose.yaml logs -f
   curl --fail http://127.0.0.1:4000/health/ready
   ```

The Compose service maps `${YTDARR_PORT:-4000}` on the host to the fixed container port `4000`; changing the host port does not alter the container listener or health probe. It keeps SQLite and its sidecars in the named `/data` volume and mounts `${YTDARR_DOWNLOADS_PATH:-./downloads}` at `/downloads`. Migrations run on startup.

## Configure and recover

Open the host port only to a trusted network or authenticated proxy, then complete [Get started](../../getting-started/). Keep `deploy/.env` private: it contains signing secrets. The optional YouTube key can be configured later in Settings; startup without it is expected, but YouTube operations are unavailable.

If readiness fails, inspect `docker compose -f deploy/compose.yaml logs`. Verify the media bind mount is writable by UID/GID `10001`, `DATABASE_PATH` points into persistent `/data`, and the generated secret values remain present. Do not delete `/data` to repair a failed startup; back it up first.

A published image should be used only when a matching real release exists. The initial Unreleased path deliberately builds locally and makes no `latest` or `edge` image promise.