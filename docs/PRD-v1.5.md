# ⚡ 《Grid Master: Cyber Network》v1.5 需求規格（持久化、多房間、行動版、介面精修）

> 2026-07-12 定案。三個主題依序實作：**A 基礎建設（R1 持久化＋R2 多房間）→
> E 行動版體驗（R3）→ C 介面精修（R4）**。
> 已定案的動線決策：main 保留為預設大廳＋開分房連結；行動版以直向手機優先。

## R1 牌局持久化（部署不掀桌）

**動機**：牌局狀態全在 Room GenServer 記憶體，後端重啟即蒸發——deploy.sh
因此在有牌局進行時拒絕部署。持久化後可隨時部署，玩家只感受到數秒斷線重連。

- **快照**：Room 每次成功的狀態變更（lobby_op／game_action／chat）後，把可持久
  欄位（status、users、seats、chat、engine、result）以 `:erlang.term_to_binary`
  存入 Postgres `room_snapshots`（room_id 主鍵、payload bytea、version、
  updated_at）。選 term 序列化而非 JSON：引擎狀態的 atom／字串鍵原樣保留，
  無還原歧義。runtime 欄位（connections／monitors／timers／npc_timer）不存。
- **還原**：`Rooms.ensure` 建房前先查快照，有則還原（`binary_to_term` 帶
  `[:safe]`）；應用開機時主動喚醒所有有快照的房間（in_game 房的 NPC 計時器
  重新排程，牌局自動繼續）。還原後所有真人視為斷線——沿用現行「遊戲中斷線
  保留座位等重連」規則。
- **版本防護**：快照帶手動遞增的 `@snapshot_version`；狀態結構改變時 bump，
  不相容的舊快照直接棄用（等同今日重啟行為），log 記載。
- **清理**：房間回到大廳且無人時刪快照（main 例外——聊天歷史跨重啟保留）；
  in_game 快照最長保留 24 小時（等斷線者回來），逾期清掃。
- **對局紀錄 `games`**：開局即建列——room_id、map（現恆 `usa`，為換圖預留）、
  started_at、initial_state（term blob：含洗好的牌庫與座位順序，重播起點）。
  自然完局補上 players jsonb（名次陣列，每人 rank／id／name 當時顯示名／
  npc 布林／powered／credits／cities，取自引擎 final_ranking）、winner_id／
  winner_name 冗餘欄、rounds、finished_at；中途結束改填 aborted_at。
  戰績查詢以 `finished_at IS NOT NULL` 過濾；name 存當時值、不外鍵 accounts
  （訪客與 NPC 無帳號列）。查看 UI（個人戰績／排行榜）留給日後。
- **動作日誌 `game_actions`**：append-only 過程紀錄——每筆成功通過
  `Engine.apply_action` 的動作寫一列（game_id、seq 流水序、round、player_id、
  action、payload jsonb、inserted_at），NPC 動作同樣入列。重播＝initial_state
  依序重套動作（引擎純函數，可重建任意時間點）。回放／觀戰快轉 UI 留給日後，
  本版只保證數據齊全可重播。
- **deploy.sh**：移除「牌局進行中拒絕部署」的阻擋（`?force` 參數保留但不再
  必要）；部署 = 直接重啟，Phoenix socket 自動重連，快照保證局面不失。

## R2 多房間

**現況**：channel 層天然支援（任何 `room:<id>` topic 自動開房），前端寫死
`room:main`。工在入口動線、路由與生命週期。

- **動線（定案）**：落地即進 main（現行不變）。main 大廳新增「＋開新房間」
  鈕（登入使用者限定，與入座同門檻）：產生房號、跳轉並提供「複製連結」。
  main 側欄顯示活躍房間列表（房號、人數、狀態）可點擊加入。
- **路由**：hash 路由，不引入 vue-router——`#/r/<id>` ↔ `room:<id>`，
  無 hash = main。切房 = leave ＋ join（沿用 reconnect 機制）。分房內顯示
  房號、「複製連結」與「回大廳」鈕。
- **房號**：4–6 字元小寫英數，排除易混淆字元（0/o、1/l）。後端 join 白名單
  `main` 或 `^[a-z0-9]{4,6}$`，不合法拒絕（防任意字串垃圾房）。
- **房間列表**：REST `GET /api/rooms`（房號、人數、status），前端進大廳時
  抓＋每 30 秒輪詢＋手動刷新。
- **生命週期**：房間進程無連線閒置 10 分鐘自動關閉（快照仍在，有人回來
  `ensure` 自動復活）；非 in_game 的分房關閉時連快照一併刪除。main 永遠
  可復活。

## R3 行動版體驗（直向手機優先）

**驗收基準**：390×844（iPhone 14 級）Playwright 裝置模擬走完整局並截圖自審；
橫向與平板順帶受益、不特別驗收。

- **版面**：直向單欄——頂欄精簡（小螢幕收合使用者資訊為圖示）、地圖全寬、
  高度隨視窗；操作 dock 與階段面板優先、其餘面板（市場／日誌）改摺疊；
  聊天摺疊為可展開區塊。
- **觸控**：互動目標 ≥44px（±鈕、座位、確認鈕、卡牌）；觸控裝置地圖縮放
  預設開啟（桌機維持預設關）。
- **細節**：modal 小螢幕全幅化、viewport meta／safe-area 檢查、消除橫向
  溢位（沿用 headless 量測法）。

## R4 介面精修（v1.3 明列的下一輪）

- **字型**：數字與拉丁字元用科技感 display 字型（自架 woff2、僅子集化拉丁＋
  數字，避免 CJK 字型體積）；中文維持系統字型。候選 Chakra Petch／Rajdhani／
  Orbitron，截圖比對後由使用者定案。
- **識別**：SVG logo（晶片／閃電圖騰，深色主題）＋favicon＋og meta（分享
  連結預覽卡）＋連線前載入畫面（splash）。
- **順帶**：標題列與 GameOver 畫面潤飾。
- **不做**：Rive（維持既有 Pixi 動畫）、音效（另案）。

## 驗證

- R1：快照 round-trip 測試（in_game 房重啟後引擎狀態一致、NPC 繼續出手）、
  版本不合棄用、完局寫入 games；**重播不變量**——initial_state 依序重套
  game_actions 必須得到與最終引擎狀態完全一致的結果（NPC 對局跑到完局驗證）；
  dev 實測重啟牌局不失，prod 部署一次驗證。
- R2：雙房並行 E2E（main 與分房各一局互不干擾）、房號連結直達、閒置回收。
- R3：iPhone viewport 全流程截圖自審後交使用者驗收。
- R4：字型與 logo 候選截圖交使用者定案後套用。

## 停點（需使用者確認）

- R4 字型候選與 logo 設計過目定案。
- 各主題完成後照慣例等「commit」「push」指示。
