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

# The tailwind and esbuild packages download their standalone CLIs on first use
# (Tailwind from GitHub releases, esbuild from the npm registry). Behind a proxy
# the release redirect's headers exceed Erlang's 10 KB limit
# ({:header_too_long, {:max, 10240}}), so fetch them here with curl and point
# the Mix tasks at the result. Keep the versions in step with config/config.exs.
ARG TARGETARCH
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) tw=x64; eb=linux-x64 ;; \
      arm64) tw=arm64; eb=linux-arm64 ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/tailwindcss \
      "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.12/tailwindcss-linux-${tw}"; \
    chmod 0755 /usr/local/bin/tailwindcss; \
    curl -fsSL "https://registry.npmjs.org/@esbuild/${eb}/-/${eb}-0.25.4.tgz" \
      | tar -xz -C /tmp; \
    install -m 0755 /tmp/package/bin/esbuild /usr/local/bin/esbuild; \
    rm -rf /tmp/package
ENV TAILWIND_PATH=/usr/local/bin/tailwindcss
ENV ESBUILD_PATH=/usr/local/bin/esbuild

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
