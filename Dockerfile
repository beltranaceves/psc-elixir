# Build stage
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1
ARG DEBIAN_VERSION=trixie-20260918-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends build-essential git curl ca-certificates openssl \
    && update-ca-certificates \
    && test -s /etc/ssl/certs/ca-certificates.crt \
    && rm -rf /var/lib/apt/lists/*

ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/runtime.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Runner stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
    && update-ca-certificates \
    && test -s /etc/ssl/certs/ca-certificates.crt \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod"

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/psc ./

USER nobody

# The Docker entrypoint does not read the Procfile, so the release tasks that
# Gigalixir runs at boot must run here too: migrations, the ADMIN_EMAILS
# bootstrap and the built-in template seed. `setup/0` is idempotent, and
# `exec` hands PID 1 to the server so stop/restart signals reach it.
CMD ["/bin/sh", "-c", "/app/bin/psc eval \"Psc.Release.setup()\" && exec /app/bin/server"]
