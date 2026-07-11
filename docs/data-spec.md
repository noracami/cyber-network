# 遊戲數據層規格（M1 Data Spec）

本文件定義 MVP 的靜態遊戲數據格式與換皮命名。數據內容經三個開源實作交叉比對＋官方規則書 PDF 仲裁查證（來源見文末）。

## 0. 檔案佈局

| 檔案 | 內容 | PRD 對應 |
|---|---|---|
| `backend/priv/data/usa_map.json` | 城市、區域、連線 | §4 |
| `backend/priv/data/cyber_decks.json` | 卡牌牌庫＋牌庫設置協議 | §4 |
| `backend/priv/data/game_rules.json` | **（新增提案）**資源市場、補給表、收入表、人數參數 | §4.2 / §5.2 |

> 新增 `game_rules.json` 的理由：補給表、收入表這類「查表數據」若寫死在 Elixir 程式裡，之後平衡調整要改程式碼；抽成 JSON 後引擎保持純函數、吃表運算。若同意，PRD §4 開頭一句需補上此檔名。

## 1. 換皮命名總表

### 1.1 世界觀詞彙

| 原版 | 換皮 | JSON id |
|---|---|---|
| 城市 | 節點 (Node) | `city` |
| 區域 | 叢集 (Cluster) | `region` |
| 電廠 | 設施（數據中心／晶圓廠） | `plant` |
| Elektro | ⚡ 能量點數 (Credits) | `credits` |
| 房屋 | 節點佔據標記 | `house` |

### 1.2 資源（燃料 → 能源）

| 原版 | 換皮顯示名 | JSON id | 市場行為（與原版相同） |
|---|---|---|---|
| 煤炭 Coal | 💧 水力 | `hydro` | 總量 24；價位 $1–8 各 3 個；初始全滿 |
| 石油 Oil | 🔥 火力／太陽能 | `thermal` | 總量 24；初始 18 個（自 $3 起填） |
| 垃圾 Garbage | ♻️ 廢料（電子廢料） | `waste` | 總量 24；初始 6 個（自 $7 起填） |
| 鈾 Uranium | 🧠 算力／量子晶片 | `quantum` | 總量 12；價位 $1–8,10,12,14,16 各 1 個；初始 $14、$16 |
| 混合（煤＋油） | 💧🔥 混合供電 | `hybrid` | 水力與火力任意組合湊數 |
| （風力廠·免燃料） | 🍃 綠能自持（零耗能） | `self` | 不需資源 |
| （核融合廠） | 🌀 奇點核心 | `fusion` | 不需資源 |

✅ **命名衝突（已解決 2026-07-12）**：PRD 原把「垃圾」換成「綠能」，與 13 號免燃料廠「純綠能廠」撞名。定案：垃圾資源改為「♻️ 廢料（電子廢料）」（id `waste`，可購買囤積、燒掉供電，符合原版燃料性質）；免燃料設施類型為「🍃 綠能自持」（id `self`）。PRD §4.1、§4.2 已同步修訂。

### 1.3 叢集（區域）命名

| JSON id | 原版顏色 | 換皮顯示名 | 城市 |
|---|---|---|---|
| `nw` | 紫 | 西北叢集 | Seattle, Portland, Boise, Billings, Cheyenne, Denver, Omaha |
| `sw` | 青 | 西南叢集 | San Francisco, Los Angeles, San Diego, Las Vegas, Phoenix, Salt Lake City, Santa Fe |
| `mw` | 黃 | 中西叢集 | Fargo, Duluth, Minneapolis, Chicago, St. Louis, Cincinnati, Knoxville |
| `sc` | 紅 | 中南叢集 | Kansas City, Oklahoma City, Dallas, Houston, Memphis, New Orleans, Birmingham |
| `ne` | 棕 | 東北叢集 | Detroit, Buffalo, Pittsburgh, Boston, New York, Philadelphia, Washington D.C. |
| `se` | 綠 | 東南叢集 | Norfolk, Raleigh, Atlanta, Savannah, Jacksonville, Tampa, Miami |

城市保留真實美國城市名（英文），視覺上以科技風節點呈現。

### 1.4 設施卡牌命名表（42 張＋Step 3）

格式：編號（=最低出價）｜類型｜燃料數 → 供電節點數｜換皮卡名。數值已三方查證。

| # | 類型 | 燃料→節點 | 卡名 |
|---|---|---|---|
| 03 | thermal | 2→1 | 老舊火力機櫃 |
| 04 | hydro | 2→1 | 水冷試驗機房 |
| 05 | hybrid | 2→1 | 混供中繼站 |
| 06 | waste | 1→1 | 單機廢料爐 |
| 07 | thermal | 3→2 | 燃氣運算棚 |
| 08 | hydro | 3→2 | 溪流水輪機房 |
| 09 | thermal | 1→1 | 屋頂日光機櫃 |
| 10 | hydro | 2→2 | 河谷水冷中心 |
| 11 | quantum | 1→2 | 初代量子實驗艙 |
| 12 | hybrid | 2→2 | 雙迴路混供站 |
| 13 | self | 0→1 | 微型綠能節點 |
| 14 | waste | 2→2 | 雙爐廢料精煉站 |
| 15 | hydro | 2→3 | 攔河堰資料中心 |
| 16 | thermal | 2→3 | 聚光太陽能塔 |
| 17 | quantum | 1→2 | 低溫量子機櫃 |
| 18 | self | 0→2 | 離網自持聚落 |
| 19 | waste | 2→3 | 近港廢料處理廠 |
| 20 | hydro | 3→5 | 大壩渦輪機廠 |
| 21 | hybrid | 2→4 | 複合能源樞紐 |
| 22 | self | 0→2 | 被動冷卻塔 |
| 23 | quantum | 1→3 | 量子退火陣列 |
| 24 | waste | 2→4 | 離岸廢料熔煉台 |
| 25 | hydro | 2→5 | 深水冷卻園區 |
| 26 | thermal | 2→5 | 沙漠日光電廠 |
| 27 | self | 0→3 | 地熱自持基地 |
| 28 | quantum | 1→4 | 光子量子矩陣 |
| 29 | hybrid | 1→4 | 智慧調度中心 |
| 30 | waste | 3→6 | 巨型廢料再生廠 |
| 31 | hydro | 3→6 | 抽蓄水力要塞 |
| 32 | thermal | 3→6 | 軌道鏡面聚能站 |
| 33 | self | 0→4 | 零碳園區 |
| 34 | quantum | 1→5 | 量子叢集主機 |
| 35 | thermal | 1→5 | 高效日光穹頂 |
| 36 | hydro | 3→7 | 峽谷超級大壩 |
| 37 | self | 0→4 | 仿生自持網 |
| 38 | waste | 3→7 | 大陸級廢料回收網 |
| 39 | quantum | 1→6 | 容錯量子核心 |
| 40 | thermal | 2→6 | 熔鹽儲能電站 |
| 42 | hydro | 2→6 | 海嶺潮汐矩陣 |
| 44 | self | 0→5 | 戴森原型節點 |
| 46 | hybrid | 3→7 | 全域能源中樞 |
| 50 | fusion | 0→6 | 奇點核心 |
| — | step3 | — | STEP 3（系統升級） |

## 2. JSON Schema

### 2.1 `usa_map.json`

```jsonc
{
  "id": "usa",
  "name": "美利堅網域",
  "regions": [
    { "id": "nw", "name": "西北叢集", "color": "#9b59b6" }
  ],
  "cities": [
    // pos 為 0–100 正規化座標（依真實地理近似），供前端渲染
    { "id": "seattle", "name": "Seattle", "region": "nw", "pos": { "x": 8, "y": 6 } }
  ],
  "edges": [
    // 無向邊；cost 0 也是合法值（原版有 3 條 0 元連線）
    { "between": ["seattle", "portland"], "cost": 3 }
  ]
}
```

- 城市 id 用 snake_case（`new_york`、`washington_dc`）。
- 共 42 城、6 叢集、**87 條邊**。
- 城市價位格（$10/$15/$20）為全地圖統一規則，放 `game_rules.json`，不放各城市。

### 2.2 `cyber_decks.json`

```jsonc
{
  "id": "standard",
  "plants": [
    { "number": 3, "type": "thermal", "fuel": 2, "powers": 1, "name": "老舊火力機櫃" },
    { "number": 13, "type": "self", "fuel": 0, "powers": 1, "name": "自持微型節點" }
    // ... 共 42 張；type: hydro|thermal|waste|quantum|hybrid|self|fusion
  ],
  "setup": {
    "initial_market": [3, 4, 5, 6],        // 現行市場（可競標）
    "initial_future": [7, 8, 9, 10],       // 未來市場
    "top_of_deck": 13,                     // 洗牌後置頂
    "step3_at_bottom": true                // Step 3 卡置底
  }
}
```

### 2.3 `game_rules.json`

```jsonc
{
  "starting_credits": 50,
  "city_slot_costs": [10, 15, 20],         // Step 1/2/3 進場費
  "resource_market": {
    "hydro":   { "total": 24, "initial": 24, "slots": "1-8x3" },
    "thermal": { "total": 24, "initial": 18, "slots": "1-8x3" },
    "waste":   { "total": 24, "initial": 6,  "slots": "1-8x3" },
    "quantum": { "total": 12, "initial": 2,  "slots": [1,2,3,4,5,6,7,8,10,12,14,16] }
    // quantum 初始 2 個放在 $14、$16
  },
  "resupply": {
    // [hydro, thermal, waste, quantum]，官方規則書表格
    "2": { "step1": [3,2,1,1], "step2": [4,2,2,1], "step3": [3,4,3,1] },
    "3": { "step1": [4,2,1,1], "step2": [5,3,2,1], "step3": [3,4,3,1] },
    "4": { "step1": [5,3,2,1], "step2": [6,4,3,2], "step3": [4,5,4,2] },
    "5": { "step1": [5,4,3,2], "step2": [7,5,3,3], "step3": [5,6,5,2] },
    "6": { "step1": [7,5,3,2], "step2": [9,6,5,3], "step3": [6,7,6,3] }
  },
  "payout": [10, 22, 33, 44, 54, 64, 73, 82, 90, 98, 105,
             112, 118, 124, 129, 134, 138, 142, 145, 148, 150],
  "player_counts": {
    "2": { "regions": 3, "removed_plants": 8, "max_plants": 4, "step2_trigger": 10, "game_end": 21 },
    "3": { "regions": 3, "removed_plants": 8, "max_plants": 3, "step2_trigger": 7,  "game_end": 17 },
    "4": { "regions": 4, "removed_plants": 4, "max_plants": 3, "step2_trigger": 7,  "game_end": 17 },
    "5": { "regions": 5, "removed_plants": 0, "max_plants": 3, "step2_trigger": 7,  "game_end": 15 },
    "6": { "regions": 5, "removed_plants": 0, "max_plants": 3, "step2_trigger": 6,  "game_end": 14 }
  }
}
```

## 3. 與 PRD 的差異（需確認）

1. **新增 `game_rules.json`**：PRD 只列兩個 JSON 檔（§4 開頭），提案加第三個。
2. ~~**「純綠能廠」改名**~~：已定案（廢料方案），見 §1.2。
3. **依人數移除電廠卡**：原版設置會依人數隨機移除 8/8/4/0/0 張卡（PRD §4.2 未提及）。建議照原版做，數據已備妥；是否啟用屬 M2 規則範圍決策。
4. **依人數限制叢集數**：原版依人數只開放 3–5 個相鄰區域。同上，數據已備妥，M2 再決定 MVP 是否實作。

## 4. 數據來源與查證

- 官方英文規則書 PDF（Rio Grande Games 版，© 2004, 2010 2F-Spiele）——補給表、收入表、人數參數的最終依據。
- [andrewswan/power-grid](https://github.com/andrewswan/power-grid)（Java）與 [SJacquesCS/Power-Grid](https://github.com/SJacquesCS/Power-Grid)（C++）——地圖 87 條連線逐條 diff 完全一致；卡牌數據三方一致。
- 已知並排除的來源錯誤：amirbawab/PowerGrid 的 XML 缺 2 條連線＋1 個成本錯誤；giannitedesco/funky 的 3 號卡欄位互換；andrewswan 的 5 人補給表複製了 4 人數值（以官方 PDF 仲裁）。
