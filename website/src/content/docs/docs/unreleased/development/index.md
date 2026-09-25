---
title: Development setup
description: Prepare the Elixir application and its separate website toolchain for local Ytdarr development.
sidebar:
  order: 1
---

Use the application toolchain for Ytdarr itself and the Node toolchain only for this documentation website. They are separate projects.

## Prerequisites

Install the versions in `.tool-versions`: Elixir `1.19.5` on Erlang/OTP `29`. The application requires Elixir `~> 1.19`, plus `yt-dlp` and `ffmpeg` on `PATH`. A YouTube Data API key is needed for live YouTube operations, but tests and ordinary startup can use isolated configuration.

## Run the application

1. Install dependencies, set up the database, and build assets:

   ```sh
   mix setup
   ```

2. Start the development server:

   ```sh
   mix phx.server
   ```

3. Visit `http://localhost:4000`. Run the test suite with `mix test`; `mix precommit` is the repository's combined quality command.

Development-only routes are useful locally but are not deployment access controls. Avoid live YouTube calls in tests; use the repository's isolated fixtures. See [architecture](./architecture/) and [contributing](./contributing/).

## Run the website separately

The static website is under `website/`. From that directory, use its own Node/npm commands:

```sh
npm ci
npm run dev
```

Website authoring does not replace Mix setup, and application dependencies do not install website dependencies. See [website authoring](./website/).