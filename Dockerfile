# 生產映像檔：前端 dist ＋ Phoenix release 合一，同源服務 SPA／API／WebSocket。
# 三個 stage 的版本對齊很重要：runtime 的 alpine 必須與 builder（elixir:1.18-alpine
# = alpine 3.24 / OTP 28）一致，否則 release 內建的 ERTS 會缺共享函式庫。

# ── Stage 1: 前端建置 ─────────────────────────────
FROM node:22-alpine AS web
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ── Stage 2: 後端 release ────────────────────────
FROM elixir:1.18-alpine AS build
RUN apk add --no-cache build-base git
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod

COPY backend/mix.exs backend/mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY backend/config ./config
COPY backend/lib ./lib
COPY backend/priv ./priv
COPY --from=web /web/dist ./priv/static

RUN mix compile && mix release

# ── Stage 3: runtime ─────────────────────────────
FROM alpine:3.24
RUN apk add --no-cache libstdc++ openssl ncurses-libs ca-certificates curl
WORKDIR /app
RUN adduser -D -h /app app

COPY --from=build --chown=app:app /app/_build/prod/rel/grid_master ./

USER app
ENV PHX_SERVER=true
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s \
  CMD curl -fsS http://localhost:4000/api/activity >/dev/null || exit 1

CMD ["bin/grid_master", "start"]
