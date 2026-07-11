FROM elixir:1.18

# Node.js 供 Vite 前端使用；inotify-tools 供 Phoenix live reload 使用。
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git inotify-tools \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /workspace
