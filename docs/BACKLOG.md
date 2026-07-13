# Backlog（未排程候選）

> 2026-07-13 v1.5 收官後整理。下個版本規劃時從這裡挑。

## 卡面美術（進行中，2026-07-14 交接）

**已完工上線**：風格定案 ligne claire 平塗四色（`tools/card-art/palette.json` 為色彩單一來源，quantize 保底）；#3 已上圖鑑。工具鏈 `tools/card-art/flatten.py`、圖鑑 `#/gallery`（含六風格比稿區，任務結束後可拆）、admin 生成工作台 `#/admin/cards`（OpenAI Batch 半價、key 前端保管、history 表）。R2：dev=`grid-master-cards`（r2.dev）、prod=`grid-master-cards-prod`（`gm-cards.miao-bao.cc`）。

**下一步（依序）**：

1. **生成 #5–#9 卡面**。prompt 模板（`[主題句]` 逐張替換）：

   ```
   ligne claire comic illustration, bold clean dark blue outlines,
   flat solid color fills, large simple shapes, limited palette
   (cream paper, dark navy, brick red, ochre yellow),
   no hatching, no shading, no gradients, no texture,
   board game card art, [主題句], plain background, no text, no numbers
   ```

   | 卡 | 主題句 |
   |---|---|
   | #5 混供中繼站 | a patched-together relay station with a fuel tank on one side and a waste chute on the other feeding one machine, tangled cables |
   | #6 單機廢料爐 | a small trash-burning furnace wired to a single lonely computer tower, scrap piles nearby |
   | #7 燃氣運算棚 | a makeshift shed of server racks powered by gas canisters and a generator |
   | #8 溪流水輪機房 | a wooden waterwheel hut beside a stream, cables running from the wheel to server racks inside |
   | #9 屋頂日光機櫃 | a rooftop server cabinet shaded by tilted solar panels, cables trailing down the wall |

2. **每張後處理兩行**（quantize → 縮 512 寬進 public）：

   ```bash
   cd tools/card-art && .venv/bin/python flatten.py quantize <原圖>
   sips --resampleWidth 512 out/<名>_quantized.png --out ../../frontend/public/cards/plant_NN.png
   ```

3. **#9 名實矛盾**：卡名「日光」但 `type: thermal`（吃燃料）——改卡名或畫面保留燃料元素，擇一。
4. **首次真實 batch 驗證**：`CardGen.parse_output` 依官方文件寫成、尚未用真 key 走過 happy path；失敗會完整記在 history 的 error_msg。
5. **對局內卡面**：`PlantCard` 仍是 SVG 紋路背景，插圖目前只在圖鑑——決定是否帶進對局 UI（小尺寸可讀性已驗證）。
6. **42 張全量生成時**：工作台加 batch 批量模式（一份 JSONL 多行請求），半價效益最大化。

**備忘**：新增跨 `frontend/` 的 import 或 `public/` 子目錄時，同步檢查 `Dockerfile` COPY 範圍與 `grid_master_web.ex` 的 `static_paths` 白名單（本地驗不到，`docker build --target web .` 可快篩）。本地 admin：`localStorage.gm_token = "dev-admin-token"`；prod admin 走 `ADMIN_DISCORD_IDS`。

## 動畫與回饋（v1.5 實測回饋，2026-07-13）

1. **終局供電動畫被跳過**：最後一次供電結算完直接切到結局頁，供電三連播（A3 事件動畫）沒機會播。應讓動畫播完再轉場（或結局頁前插一拍）。
2. **設施市場卡牌放大**：圖卡（發電廠）大小加倍，卡上每個 icon 與數字也加倍。
3. **採購資源的取得回饋**：資源從市場「飛」到玩家狀態卡的動畫；或在玩家狀態卡上做資源補充動畫，依順序每個玩家輪流顯示。
4. **供電收入回饋**：玩家狀態卡跳出「+N」數字動畫，輪流顯示。

## 既有候選（v1.5 規劃時未入選）

- **B 求勝 NPC**：現行 NPC 只求合法不求贏（偏好候選清單）。
- **D 台灣地圖**：換圖需重算世界尺寸與節點大小（受最擠城市對限制，見 M9 註記）。

## 數據已就緒、UI 未做（v1.5 R1 留的地基）

- 個人戰績／排行榜（`games` 表，`finished_at IS NOT NULL` 過濾）。
- 對局回放／觀戰快轉（`game_actions` ＋ `Replay.run`，重播不變量測試已守恆）。
