# Grid Master: Cyber Network

致敬《電力公司（Power Grid）》的多人連線網頁遊戲（非商業粉絲作品）。完整規格見 `docs/PRD.md`，動工前先讀。

## 結構

- `backend/` — Elixir/Phoenix。`lib/grid_master/` 放純遊戲邏輯（engine / room / data），`lib/grid_master_web/` 放 Channels 與 API。地圖與卡牌數據放 `priv/data/*.json`（snake_case 檔名）。後端另有 Phoenix 生成的 `AGENTS.md` 記載框架慣例。
- `frontend/` — Vue 3 + Vite + Pinia。**JS + JSDoc，不用 TypeScript**；`jsconfig.json` 已開 `checkJs`。PixiJS 渲染層放 `src/game/`，與 Vue 元件（`src/components/`）分離，只透過 Pinia store 溝通。
- `deploy/` — 生產部署範本（compose／env／deploy.sh，實際檔案在 wisp VM 的 `/opt/grid-master/`）。根目錄 `Dockerfile` 是單一多階段映像檔（前端 dist 包進 Phoenix release 同源服務）。CI/CD 見 `.github/workflows/deploy.yml` 與 PRD §6。
- 開發跑在 devcontainer 內；`_build/`、`deps/`、`node_modules/` 存於 named volumes，宿主機上看不到內容屬正常。
- DB 主機名預設 `db`（compose service 名）；在宿主機直接跑 mix 時需設 `PGHOST=localhost`。

## 慣例

- 遊戲規則邏輯寫成純函數放 `engine/`，GenServer 只做狀態容器與訊息路由——規則可以不開 WebSocket 直接用 `mix test` 測。
- MVP 遊戲狀態全在記憶體（GenServer），資料庫僅保留給未來的持久化需求。
