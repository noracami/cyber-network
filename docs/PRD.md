# ⚡ 《Grid Master: Cyber Network》第一版開發規格說明書 (PRD)

## 1. 專案範疇與 MVP 目標

本專案是一款**致敬經典桌遊《電力公司（Power Grid / Funkenschlag）》**的多人連線網頁遊戲，不需下載大廳、直覺、任務導向。核心遊戲規則完整沿用《電力公司》的系統設計，僅在主題與美術上全面換皮（Reskin）為科技風。第一階段（MVP / First Version）跳過動態編輯器的 UI 開發，**以硬編碼（Hard-coded）載入基本版美國地圖與科技主題卡牌牌庫**。
視覺風格走 **2.5D / 2D 向量科技風**（Cyberpunk 或極簡扁平風）。

---

## 2. 系統架構與技術選型 (Technical Stack & Infrastructure)

本專案全面走向「全容器化 (Docker All the Way)」的工程架構，確保本地開發環境與雲端生產環境 100% 一致。

### 2.1 後端架構 (Backend)

* **核心語言與框架**：**Elixir / Phoenix (BEAM VM)**
* **選型理由**：利用 Phoenix Channels 處理 WebSocket 極低延遲的雙向通訊。採用 **Actor Model** 設計，**將「每個遊戲房間」獨立開成一個 GenServer 進程**。所有玩家的競標、購買事件進入進程的 Mailbox 自動序列化排隊處理，**天生免疫併發衝突（Race Condition），MVP 階段完全不需要寫排他鎖（Mutex）或引入 Redis**。


* **輔助運算（選配）**：**Rust (透過 Rustler 整合至 Elixir)**
* **選型理由**：若未來地圖尋路（Dijkstra）或 AI 運算遭遇效能瓶頸，可將純運算邏輯交由 Rust 處理。



### 2.2 前端架構 (Frontend)

* **全域骨架與狀態**：**Vue 3 (Composition API) + Vite + Pinia**
* **選型理由**：Pinia 負責儲存從 WebSocket 接收到的最新房間全域狀態與使用者喜好設定。


* **核心地圖渲染**：**PixiJS (2D WebGL 渲染引擎)**
* **選型理由**：放棄複雜的純 3D 渲染，改用 2.5D 斜 45 度角的科技感地圖面板。利用 WebGL 強大效能，實現流暢的卡牌翻轉、電網電流發光粒子特效，在手機與電腦網頁皆能穩 60 幀。


* **動態 UI 與過場動畫**：**Rive (內建狀態機的互動向量動畫庫)**
* **選型理由**：負責所有科技感側邊欄展開、玩家頭像狀態切換（如 Pass 蓋章動畫）、全域回合過場動畫。前端只需將 Pinia 的布林值傳給 Rive 組件，即可完美同步動畫，代碼極度乾淨。



### 2.3 基礎建設與 DevOps (Infrastructure)

* **本地開發環境**：**VS Code Devcontainer (Mount 實體代碼)**
* **配置要點**：使用單一萬能容器（Base 使用 `elixir` 並安裝 `nodejs`）。為了避免 macOS/Windows 的 I/O 效能瓶頸，將後端的 `_build/`、`deps/` 以及前端的 `node_modules/` 使用 **Docker Named Volumes** 隔離在容器內部，不與本地硬碟同步。


* **線上部署環境**：**既有 GCP VM「wisp」（與其他 side projects 共架，Docker Compose）**
* **選型理由**：已有多個專案以相同模式穩定運行，零新增基礎設施成本。容器只綁 `127.0.0.1`，VM 不開對外服務 port。（2026-07-12 修訂，原案為新開 COS VM）


* **網路入口**：**Cloudflare Tunnel（cloudflared）**
* **選型理由**：TLS 憑證與 DNS 全由 Cloudflare 處理，免 Caddy／Let's Encrypt／固定 IP 管理，同樣避開 GCP Load Balancer 的 WebSocket 斷線坑。注意：Cloudflare 會切斷閒置 100 秒的連線，Phoenix Channel 預設 30 秒 heartbeat 天然滿足保活需求。（2026-07-12 修訂，原案為 Caddy）



---

## 3. 遊戲外（Meta-game）功能需求

### 3.1 頁面生命週期與房間狀態

遊戲頁面不設計獨立大廳，單一網頁僅在以下四個狀態間進行單向/逆向輪轉：


$$\text{等待開始遊戲 (Lobby)} \longrightarrow \text{遊戲中 (In-Game)} \longrightarrow \text{遊戲結束 (Game Over)} \longrightarrow \text{等待開始遊戲 (Lobby)}$$

### 3.2 身份與角色解耦

* **全域身份**：`Guest`（未登入訪客）、`Discord User`（已登入使用者）、`Admin`（管理員，開發期提供專屬 API/UI 可任意手動調整連線者的身份）。
* **遊戲角色**：`Player`（已入座玩家，上限 6 人）、`Spectator`（旁觀者）。
* **入座門檻（2026-07-12 定案）**：僅 `Discord User` 與 `Admin` 可入座成為 Player；`Guest` 只能旁觀與聊天。

### 3.3 核心功能矩陣

* **斷線重連**：【要】透過 Discord ID 進行 Session 綁定，重整網頁或網路抖動時自動恢復原有座位與個人遊戲盤面。
* **斷線逾時清理**：【要】等待階段若 Player 離線超過 $120$ 秒，系統自動取消其準備狀態並強制離座變回 Spectator。
* **聊天室歷史紀錄**：【要】分頁標籤包含 `All` / `Chat` / `Sysmsg`。後端 GenServer 記憶體內快取最近 $50$ 則訊息，供重連者讀取。
* **Admin 掀桌鍵**：【要】提供全域 `ABORT_GAME` API，Admin 可隨時強制清空進行中的遊戲盤面，退回 Lobby 狀態。
* **Auto-Pass 輔助功能**：【MVP 先不要】喜好設定目前純粹保留在前端視覺層（如黑夜模式），不侵入後端狀態機。

---

## 4. 遊戲中（In-Game）換皮數據規格 (Reskin Specification)

MVP 階段地圖與卡牌採用靜態 JSON 檔案（`usa_map.json` / `cyber_decks.json`，置於後端 `priv/data/`）直接由後端讀取。數據結構（城市節點、連線權重、卡牌數值）忠實對應《電力公司》原版美國地圖與牌庫，僅替換命名與視覺主題。

### 4.1 主題換皮對照表

* **貨幣**：Elektro $\longrightarrow$ **⚡ 能量點數 (Energy Credits)**
* **發電廠**：電廠卡牌 $\longrightarrow$ **🌐 數據中心 / 晶圓廠卡牌**
* **地圖**：**🗺️ 基本版美國地圖**（MVP 直接沿用《電力公司》原版美國地圖的城市節點與連線權重，僅替換為科技風視覺；台灣電網地圖列為後續版本的擴充目標）
* **燃料資源**：
* 煤炭 $\longrightarrow$ **💧 水力 / 基礎電力**
* 石油 $\longrightarrow$ **🔥 火力 / 太陽能**
* 垃圾 $\longrightarrow$ **♻️ 廢料 / 電子廢料再生**
* 核能 $\longrightarrow$ **🧠 算力 / 量子晶片**
* （免燃料廠）$\longrightarrow$ **🍃 綠能自持設施**（不需購買任何資源）



### 4.2 初始資料狀態

* **玩家初始狀態**：金錢固定為 $50$ Credits，初始房屋（節點標記）為 0，卡牌與資源庫存皆為 0。
* **資源市場初始化**：長條型陣列堆疊，水力（極充沛，自 $1 開填）、火力（中等，自 $3 開填）、廢料（稀少，自 $7 開填）、算力（極稀少，僅在 $14、$16 價位各放 1 個）。
* **卡牌牌庫協議**：初始市場固定抽取編號 `03` 至 `10` 共 8 張。將 `13` 號（首張綠能自持設施）置於牌庫頂，`Step 3` 卡固定置於牌庫底，其餘隨機洗勻。

---

## 5. 後端核心運算系統（Core Engine）

後端 GenServer 必須嚴格執行以下三大圖論與動態經濟邏輯：

### 5.1 反向順位平衡系統 (Turn Order System)

每回合開始時重新計算玩家排序：地圖上佔領節點最多者排第一；若相同，則手牌中卡牌編號最大者排第一。

* *競標卡牌階段*：由順位第 1 名（領先者）開始。
* *買資源與擴建電網階段*：**完全反轉，由最後一名（落後者）優先行動**。

### 5.2 動態定價市場系統

玩家購買資源時，由便宜的價位逐一取走，成本即時遞增。每回合結束時，後端根據「當前 Step (1, 2, 3)」與「實際玩家人數」查表，從市場最貴的空格反向注入資源。

### 5.3 圖論網路連通系統

地圖結構定義為**加權無向圖 (Weighted Undirected Graph)**。

* **城市節點 (Node)**：每個城市包含三個階梯式價位格（Slot 0: $10, Slot 1: $15, Slot 2: $20）。格子的開放取決於全域大階段（`Step 1/2/3`）。
* **連線費用計算**：擴建時，後端系統必須使用 **Dijkstra / BFS 演算法**，計算該玩家「已佔領的網路」到「目標城市」之間，**Edge 權重（過路費）加總最低的路徑**，並加上目標城市的進場格子費，得出總消耗金錢。

---

## 6. CI/CD 自動化通車管線 (Deployment Pipeline)

採用 **Image-Driven（映像檔驅動）** 的自動化部署管線。（2026-07-12 修訂：registry 由 GAR 改為 GHCR、部署觸發改用 VM 上既有的 webhook 服務、前後端合併為單一映像檔）

```
[Push to main] ➔ GitHub Actions
   ① mix test（掛 Postgres service container；不過就不部署）
   ② docker build 單一多階段映像檔（node 建前端 dist → Elixir release，
      dist 放入 priv/static 由 Phoenix 同源服務）
   ③ push ghcr.io/<owner>/grid-master:{sha, latest}
   ④ 呼叫 wisp 的 webhook（cloudflared ingress /hooks/*）
                        ⬇
[wisp VM] webhook 腳本：docker compose pull && docker compose up -d
                        && docker image prune -f
```

1. **GitHub Actions 階段**：前後端打包為**單一映像檔**——Phoenix 同源服務 SPA、`/api` 與 WebSocket，免去 Nginx 容器與跨域設定；`mix test` 是部署閘門。在 CI 上 build 也避免消耗 VM 珍貴的磁碟空間（builder 環境不落地 VM）。
2. **VM 部署階段**：`~/grid-master/` 只放 `docker-compose.prod.yml`（引用 GHCR image、綁 `127.0.0.1:8100`、Postgres sidecar）與 `.env`（SECRET_KEY_BASE／ADMIN_TOKEN／Discord 金鑰／PG 密碼）。對外由 Cloudflare Tunnel 的 `gridmaster.miao-bao.cc → localhost:8100` ingress 分流。
3. **已知限制**：遊戲狀態全在 GenServer 記憶體，部署重啟會清空進行中牌局。webhook 腳本部署前應先查詢是否有進行中對局，有則中止部署（提供 force 參數覆寫）。

---

## 7. 版權聲明與致謝 (Disclaimer & Credits)

本專案為**非商業性質的粉絲致敬作品（Fan Tribute）**，遊戲機制致敬 Friedemann Friese 設計的經典桌遊《電力公司（Power Grid / Funkenschlag）》。

* 本專案與原設計師 Friedemann Friese、原出版社 **2F-Spiele** 及英文版出版社 **Rio Grande Games** 均**無任何隸屬、授權或合作關係**。
* 本專案**不使用**原作的任何美術素材、商標、名稱與文字內容；所有視覺元件、卡牌插圖與主題命名均為全新製作。
* 本專案**不收取任何費用**，無內購、無廣告、無任何商業變現行為，僅供私人朋友間遊玩與程式開發學習用途。
* 《Power Grid》與《Funkenschlag》為其各自權利人之商標。若權利人對本專案有任何疑慮，請與開發者聯繫，我們將立即配合處理。

上述聲明需同步顯示於遊戲頁面的頁尾（Footer）或「關於」彈窗中。



