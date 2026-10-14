# Grid Master: Cyber Network

致敬《電力公司（Power Grid）》的多人連線網頁遊戲（非商業粉絲作品）。完整規格見 `docs/PRD.md`，動工前先讀。

## 結構

- `backend/` — Elixir/Phoenix。`lib/grid_master/` 放純遊戲邏輯（engine / room / data），`lib/grid_master_web/` 放 Channels 與 API。地圖與卡牌數據放 `priv/data/*.json`（snake_case 檔名）。後端另有 Phoenix 生成的 `AGENTS.md` 記載框架慣例。
- `frontend/` — Vue 3 + Vite + Pinia。**JS + JSDoc，不用 TypeScript**；`jsconfig.json` 已開 `checkJs`。PixiJS 渲染層放 `src/game/`，與 Vue 元件（`src/components/`）分離，只透過 Pinia store 溝通。
- `deploy/` — 正式環境的 env 範本（實際值在 Dokploy）。根目錄 `Dockerfile` 是單一多階段映像檔（前端 dist 包進 Phoenix release 同源服務）。CI 見 `.github/workflows/ci.yml`，發版見下方「發版」。
- 開發跑在 devcontainer 內；`_build/`、`deps/`、`node_modules/` 存於 named volumes，宿主機上看不到內容屬正常。
- DB 主機名預設 `db`（compose service 名）；在宿主機直接跑 mix 時需設 `PGHOST=localhost`。

## 慣例

- 遊戲規則邏輯寫成純函數放 `engine/`，GenServer 只做狀態容器與訊息路由——規則可以不開 WebSocket 直接用 `mix test` 測。
- MVP 遊戲狀態全在記憶體（GenServer），資料庫僅保留給未來的持久化需求。

## 發版（release PR → Dokploy）

**一般 PR merge 進 `main` 不會部署，merge release PR 才會**——也就是改了 `backend/mix.exs` 裡 `version` 的 PR。
那次 push 時 `.github/workflows/release.yml` 看到版號 X.Y.Z 還沒有 `vX.Y.Z` tag，就跑測試（呼叫 `ci.yml`）、
build image（tag `:X.Y.Z`、`:X.Y`、`:latest`、`:<sha>`，推到 ghcr）、打 Dokploy webhook，成功後才在該 commit
打上 `vX.Y.Z` 當作「已上線」的紀錄。版號已經有 tag 的 push 會被跳過。部署失敗就修好原因、手動重跑 workflow
（`workflow_dispatch`）；因為還沒打 tag，會再試一次。不要手動推 `v*` tag。

deploy job 跑在 GitHub Environment **`production`**：要審核者（目前是 @noracami）在 Actions run 裡核准才會執行，
而且只有 main 能部署。`DOKPLOY_WEBHOOK` 是這個 environment 的 secret，不是 repo 的，其他 workflow 讀不到。

**什麼時候該提議發版（agent）**——只提議，不要自己動手：

- 剛 merge 了一個改到 `backend/` 或 `frontend/`（或 `Dockerfile`）的 PR；
- 使用者要求部署或上線；
- session 開始時 `git log $(git describe --tags --match 'v*' --abbrev=0)..origin/main --oneline -- backend frontend Dockerfile` 不是空的（提一次就好）。

**沒有使用者同意，絕對不要 merge release PR**——merge 就是部署到正式站。

**步驟：**

1. 找出還沒發的 PR：上一個 tag 之後 merge 的 PR。
   ```sh
   LAST=$(git describe --tags --match 'v*' --abbrev=0)
   git log --merges --first-parent "$LAST"..origin/main --format='%s'   # "Merge pull request #N …"
   gh pr view <N> --json title,files                                   # 逐一看
   ```
   在這之前直接 push 到 main 的 commit 沒有 PR，就用 commit 的標題。
2. 決定版號：有新功能 → minor，只有修正 → patch。1.0 之前，不相容的改變也只升 minor。沒有值得發的就不發。
   這個 repo 的 commit／PR 標題不是 conventional commits，要看內容判斷。
3. 開 branch，改 `backend/mix.exs` 的 `version`，在 `CHANGELOG.md` 最上面加一節——**一個 PR 一行**，
   分「新功能」／「修正」，連結 PR：`* <PR 標題> ([#N](https://github.com/noracami/cyber-network/pull/N))`。
   以 PR 為單位，不要看 commit：用 merge commit 時同一個改動在 `git log` 會出現兩次。
4. 開 PR，標題 `發版 X.Y.Z`，只含版號與 CHANGELOG。不要在功能 PR 裡順便改版號：改版號的那個 PR 就是發版。
5. merge 前看一下 `https://gridmaster.miao-bao.cc/api/activity`：`in_game` 不是 0 表示有人在玩。重啟會寫快照、
   重啟後續局，但玩家會斷線幾秒；能等就等。
6. merge 後就會部署。確認 *Release* run 成功、`vX.Y.Z` 有打上、`/api/activity` 回 200。

回滾：在 Dokploy 把 image 改成之前的 `:X.Y.Z` 再 redeploy。**版號打過 tag 就不再重用。**
