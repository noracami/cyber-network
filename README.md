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

## 文件

- [docs/PRD.md](docs/PRD.md) — 開發規格說明書（PRD）
