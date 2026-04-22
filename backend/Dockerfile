# ── Build stage ───────────────────────────────────────────────
FROM elixir:1.16-alpine AS builder

RUN apk add --no-cache git build-base nodejs npm

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Fetch deps (layer-cached if mix.exs unchanged)
COPY mix.exs mix.lock ./
ENV MIX_ENV=prod
RUN mix deps.get --only prod
RUN mix deps.compile

# Compile app
COPY config config/
COPY lib    lib/
COPY priv   priv/

RUN mix compile

# Build release
RUN mix release

# ── Runtime stage ─────────────────────────────────────────────
FROM alpine:3.19 AS runtime

RUN apk add --no-cache libstdc++ openssl ncurses-libs curl

WORKDIR /app

RUN addgroup -S chat && adduser -S chat -G chat

COPY --from=builder --chown=chat:chat /app/_build/prod/rel/chat ./

RUN mkdir -p /app/priv/uploads && chown -R chat:chat /app/priv

USER chat

EXPOSE 8080

ENV PHX_SERVER=true
ENV MIX_ENV=prod

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/app/bin/chat", "start"]
