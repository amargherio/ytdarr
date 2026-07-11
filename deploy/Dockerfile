ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5.0.3
ARG DEBIAN_VERSION=bookworm-20260623-slim
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV=prod

COPY VERSION mix.exs mix.lock ./
RUN mix deps.get --only prod

RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY assets assets
RUN mix assets.setup \
  && mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS final

ARG YT_DLP_VERSION=2026.07.04
ARG YT_DLP_SHA256=6bbb3d314cde4febe36e5fa1d55462e29c974f63444e707871834f6d8cc210ae
ARG VCS_REF=unknown
ARG VERSION=dev

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    libncurses6 \
    libstdc++6 \
    locales \
    openssl \
    tini \
  && curl -fsSL \
    "https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp_linux" \
    -o /usr/local/bin/yt-dlp \
  && echo "${YT_DLP_SHA256}  /usr/local/bin/yt-dlp" | sha256sum -c - \
  && chmod 0755 /usr/local/bin/yt-dlp \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 ytdarr \
  && useradd --system --uid 10001 --gid ytdarr --home-dir /app --shell /usr/sbin/nologin ytdarr \
  && mkdir -p /app /data /downloads \
  && chown -R ytdarr:ytdarr /app /data /downloads

WORKDIR /app

ENV DATABASE_PATH=/data/ytdarr.db \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

COPY --from=builder --chown=ytdarr:ytdarr /app/_build/prod/rel/ytdarr ./
COPY --chown=ytdarr:ytdarr deploy/docker-entrypoint.sh /usr/local/bin/ytdarr-entrypoint

RUN chmod 0755 /usr/local/bin/ytdarr-entrypoint

LABEL org.opencontainers.image.source="https://github.com/amargherio/ytdarr" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}"

USER ytdarr

EXPOSE 4000
VOLUME ["/data", "/downloads"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["curl", "--fail", "--silent", "--show-error", "http://127.0.0.1:4000/health/ready"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/ytdarr-entrypoint"]
CMD ["/app/bin/server"]