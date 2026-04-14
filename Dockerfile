# === Stage 1: Builder ===
FROM elixir:1.17-otp-27-alpine AS builder

ENV MIX_ENV=prod

RUN apk add --no-cache build-base git

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy dependency manifests first for layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application source
COPY config config
COPY lib lib
COPY priv priv
COPY rel rel

# Compile and build release
RUN mix compile
RUN mix release

# === Stage 2: Runner ===
FROM alpine:3.20 AS runner

ENV MIX_ENV=prod

RUN apk add --no-cache libstdc++ libgcc ncurses-libs

WORKDIR /app

# Create non-root user
RUN addgroup -S sle && adduser -S sle -G sle

# Copy release from builder
COPY --from=builder --chown=sle:sle /app/_build/prod/rel/sle ./

USER sle

EXPOSE 4000

ENTRYPOINT ["bin/sle"]
CMD ["start"]
