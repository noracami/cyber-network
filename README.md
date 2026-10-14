# ⚡ Grid Master: Cyber Network

致敬經典桌遊《電力公司（Power Grid）》的多人連線網頁遊戲——競標數據中心、擴建網路節點、搶佔算力資源，科技風全面換皮。

> 本專案為**非商業粉絲致敬作品**，與原設計師 Friedemann Friese、2F-Spiele 及 Rio Grande Games 無任何隸屬或授權關係。詳見 [docs/PRD.md](docs/PRD.md) 第 7 節。

## 技術架構

- **後端**：Elixir / Phoenix — 每個遊戲房間一個 GenServer，Phoenix Channels 處理 WebSocket
- **前端**：Vue 3 + Pinia + PixiJS（JS + JSDoc，不用 TypeScript）
- **開發環境**：VS Code Devcontainer，全容器化

## 開發環境啟動

1. 安裝 Docker（或 OrbStack）與 VS Code + Dev Containers 擴充功能
2. 用 VS Code 開啟本資料夾 → 「Reopen in Container」
3. 容器內分別啟動前後端：

   ```sh
   cd backend && mix deps.get && mix ecto.create && mix phx.server   # http://localhost:4000
   cd frontend && npm install && npm run dev                          # http://localhost:5173
   ```

## 部署

正式站：https://gridmaster.miao-bao.cc （單台 GCP VM 上的 [Dokploy](https://dokploy.com)，對外走 Cloudflare Tunnel）

一般 PR merge 進 `main` 只跑測試，**不會部署**。merge 改了 `backend/mix.exs` 版號的 release PR 才會：
GitHub Actions 跑 `mix test`（閘門）→ 核准 → build 單一映像檔（前端 dist 由 Phoenix 同源服務）
推到 `ghcr.io/noracami/cyber-network` → 觸發 Dokploy 部署 → 打 `vX.Y.Z` tag。
流程見 [CLAUDE.md](CLAUDE.md)，版本紀錄見 [CHANGELOG.md](CHANGELOG.md)，正式環境的 env 範本見
[deploy/env.example](deploy/env.example)。

牌局狀態在記憶體裡，重啟前會寫快照到 Postgres、重啟後續局；部署時 Swarm 用 `stop-first`
（先停舊的再起新的），不會有兩個副本同時持有房間。

## 文件

- [docs/PRD.md](docs/PRD.md) — 開發規格說明書（PRD）
