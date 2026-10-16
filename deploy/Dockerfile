# Override BASE_IMAGE with a pinned entry from native-targets.tsv for native targets.
ARG BASE_IMAGE=docker.io/library/ubuntu@sha256:f610ab94648195aa356059f5b41d6085c9d4d903c072430cdd1af7bdb646106b
FROM ${BASE_IMAGE} AS runtime
COPY deploy/scripts/native-packages.sh deploy/scripts/native-toolchain.sh /build-inputs/
COPY deploy/native-downloads.tsv /build-inputs/
RUN bash /build-inputs/native-packages.sh runtime \
  && bash /build-inputs/native-toolchain.sh runtime
ENV LANG=C.UTF-8

FROM runtime AS toolchain
COPY .tool-versions /build-inputs/.tool-versions
ARG NATIVE_BUILD_JOBS=4
RUN bash /build-inputs/native-packages.sh build \
  && bash /build-inputs/native-toolchain.sh build
ENV PATH="/opt/elixir/bin:${PATH}" MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

FROM toolchain AS builder
WORKDIR /app
COPY VERSION mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile
COPY priv priv
COPY lib lib
RUN mix compile --warnings-as-errors
COPY assets assets
RUN mix assets.setup && mix assets.deploy
COPY config/runtime.exs config/
COPY rel rel
RUN mix release --overwrite
COPY deploy/scripts/package-native.sh deploy/scripts/package-native.sh

FROM builder AS packaged
ARG VCS_REF
RUN VCS_REF="${VCS_REF}" bash deploy/scripts/package-native.sh /app /out

FROM runtime AS artifacts
COPY --from=packaged /out /out

FROM runtime AS final
ARG VCS_REF=unknown
ARG VERSION=dev
RUN groupadd --system --gid 10001 ytdarr \
  && useradd --system --uid 10001 --gid ytdarr --home-dir /app --shell /usr/sbin/nologin ytdarr \
  && mkdir -p /app /data /downloads \
  && chown -R ytdarr:ytdarr /app /data /downloads
WORKDIR /app
ENV DATABASE_PATH=/data/ytdarr.db PHX_SERVER=true PORT=4000
COPY --from=builder --chown=ytdarr:ytdarr /app/_build/prod/rel/ytdarr ./
COPY deploy/docker-entrypoint.sh /usr/local/bin/ytdarr-entrypoint
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
