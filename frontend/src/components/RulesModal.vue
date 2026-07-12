<script setup>
import { computed } from 'vue'
import { RESOURCE_META } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'
import { useUiStore } from '../stores/ui'

const ui = useUiStore()
const room = useRoomStore()
const staticStore = useStaticStore()

const TABS = [
  ['flow', '流程'],
  ['auction', '競標'],
  ['resources', '資源'],
  ['building', '擴建'],
  ['power', '供電'],
  ['end', '終局'],
  ['about', '關於'],
]

const RESKIN = [
  ['貨幣 Elektro', '⚡ 能量點數 (Credits)'],
  ['發電廠', '🌐 數據中心／晶圓廠'],
  ['煤炭', '💧 水力'],
  ['石油', '🔥 火力'],
  ['垃圾', '♻️ 廢料'],
  ['核能', '🧠 算力'],
  ['免燃料廠', '🍃 綠能自持設施'],
]

const rules = computed(() => staticStore.rules)

/** 進行中牌局的玩家人數（不在牌局中為 null）——用來高亮對照表 */
const playerCount = computed(() =>
  room.game ? Object.keys(room.game.players).length : null
)

const slotCosts = computed(() => rules.value?.city_slot_costs || [])
const resupplyOrder = computed(() => rules.value?.resupply_order || [])

const resupplyRows = computed(() =>
  Object.entries(rules.value?.resupply || {})
    .map(([count, steps]) => ({ count: Number(count), ...steps }))
    .sort((a, b) => a.count - b.count)
)

const paramRows = computed(() =>
  Object.entries(rules.value?.player_counts || {})
    .map(([count, params]) => ({ count: Number(count), ...params }))
    .sort((a, b) => a.count - b.count)
)

const payoutRows = computed(() =>
  (rules.value?.payout || []).map((income, powered) => ({ powered, income }))
)

/** @param {number[]} amounts step 補貨量（依 resupply_order 排列） */
function resupplyText(amounts) {
  return amounts
    .map((qty, index) => `${RESOURCE_META[resupplyOrder.value[index]]?.icon || ''}${qty}`)
    .join(' ')
}
</script>

<template>
  <div v-if="ui.rulesTab" class="modal-mask top-aligned" @click.self="ui.closeRules()">
    <div class="modal-box rules-modal">
      <div class="rules-head">
        <h3>📖 規則說明</h3>
        <button class="modal-close" @click="ui.closeRules()">✕</button>
      </div>

      <div class="rules-tabs">
        <button
          v-for="[key, label] in TABS"
          :key="key"
          class="tab"
          :class="{ active: ui.rulesTab === key }"
          @click="ui.rulesTab = key"
        >
          {{ label }}
        </button>
      </div>

      <div class="rules-body">
        <!-- 流程 -->
        <template v-if="ui.rulesTab === 'flow'">
          <p>每回合依序五個階段：</p>
          <ol>
            <li><strong>決定順位</strong>（自動）——城市多者排前；平手比手上最大卡號。首回合順位隨機，該回合競標結束後立即重排。</li>
            <li><strong>競標設施</strong>——由順位第 1（領先者）開始提名。</li>
            <li><strong>採購資源</strong>——<strong>反序</strong>，落後者先買。</li>
            <li><strong>擴建網路</strong>——<strong>反序</strong>，落後者先建。</li>
            <li><strong>官僚結算</strong>——全員同時提交供電計畫，結算收入、補貨、市場輪替。</li>
          </ol>
          <p class="hint">反向順位是核心平衡機制：領先者先被迫出手競標，落後者享有便宜資源與建地優先權。</p>

          <h4>人數參數</h4>
          <table class="rules-table">
            <thead>
              <tr><th>人數</th><th>啟用叢集</th><th>移除卡牌</th><th>設施上限</th><th>Step 2 觸發</th><th>終局城數</th></tr>
            </thead>
            <tbody>
              <tr v-for="row in paramRows" :key="row.count" :class="{ hl: row.count === playerCount }">
                <td>{{ row.count }}</td>
                <td>{{ row.regions }}</td>
                <td>{{ row.removed_plants }}</td>
                <td>{{ row.max_plants }}</td>
                <td>{{ row.step2_trigger }} 城</td>
                <td>{{ row.game_end }} 城</td>
              </tr>
            </tbody>
          </table>
        </template>

        <!-- 競標 -->
        <template v-else-if="ui.rulesTab === 'auction'">
          <ul>
            <li>輪到提名者從<strong>現行市場</strong>（上排 4 張）選一張卡喊起標價（不得低於卡號），或宣告本回合不買——<strong>第 1 回合每人必須買一座</strong>。</li>
            <li>尚未買到設施的玩家輪流<strong>加價或退出</strong>；只剩一人時成交付款取卡。</li>
            <li>買到設施者本階段不再參與；提名人若沒得標，可再次提名。</li>
            <li>下排<strong>未來市場</strong>只能預覽不能買（Step 3 起市場縮為 6 張、全部可競標）。</li>
            <li>設施超過上限（見流程分頁的人數參數）需<strong>棄置一座</strong>（不能棄剛買的）；棄卡後裝不下的資源自動丟棄（保留最貴的）。</li>
            <li>整回合無人買卡 → 官僚階段將現行市場最低卡移除。</li>
            <li>市場輪替：Step 1/2 每回合把未來市場最高卡收入牌庫底；卡號 ≤ 任何玩家城市數的卡會被淘汰換新。</li>
          </ul>
        </template>

        <!-- 資源 -->
        <template v-else-if="ui.rulesTab === 'resources'">
          <ul>
            <li>反序採購（落後者先），輪到時一次提交整批。</li>
            <li>永遠從<strong>最便宜的格位</strong>買起，單價隨存量遞增——盤面的「資源市場」面板即時顯示格位與下一顆價格。</li>
            <li><strong>儲存上限</strong>：自己所有設施的燃料需求 ×2 加總（混合設施的容量可裝水力或火力）。</li>
            <li>官僚階段依「人數 × Step」查表補貨，往便宜端的空格補回。</li>
          </ul>

          <h4>每回合補貨量</h4>
          <table class="rules-table">
            <thead>
              <tr><th>人數</th><th>Step 1</th><th>Step 2</th><th>Step 3</th></tr>
            </thead>
            <tbody>
              <tr v-for="row in resupplyRows" :key="row.count" :class="{ hl: row.count === playerCount }">
                <td>{{ row.count }}</td>
                <td>{{ resupplyText(row.step1) }}</td>
                <td>{{ resupplyText(row.step2) }}</td>
                <td>{{ resupplyText(row.step3) }}</td>
              </tr>
            </tbody>
          </table>
        </template>

        <!-- 擴建 -->
        <template v-else-if="ui.rulesTab === 'building'">
          <ul>
            <li>反序進行；輪到時可<strong>連建多城</strong>，按「結束擴建」交棒。</li>
            <li>費用 = <strong>進場費 ＋ 連線費</strong>。進場費依你是該城第幾個進駐者：<template v-for="(cost, index) in slotCosts" :key="index"><template v-if="index > 0">／</template>${{ cost }}</template>；連線費是「你的網路到該城」的最低過路費總和（Dijkstra），<strong>第一座城免連線費</strong>。</li>
            <li>城市的第 2、3 格分別要到 <strong>Step 2、Step 3</strong> 才開放；同一城不能重複進駐。</li>
            <li>只能建在啟用的叢集內（依人數啟用，地圖上未啟用區域反灰）。</li>
            <li><strong>Step 2 觸發</strong>：有人達到觸發城數時，擴建階段結束即進入 Step 2，並移除現行市場最低卡。</li>
            <li><strong>Step 3 卡</strong>被抽出時：公告、重洗剩餘牌庫，於當前階段結束後進入 Step 3。</li>
          </ul>
        </template>

        <!-- 供電 -->
        <template v-else-if="ui.rulesTab === 'power'">
          <ul>
            <li>官僚階段全員<strong>同時</strong>選擇要啟動的設施（可全不啟動），資源足夠才能送出。</li>
            <li>啟動的設施各消耗其燃料需求、貢獻其供電數；<strong>實際供電數不超過你的城市數</strong>。</li>
            <li>混合設施可用水力／火力任意組合；🍃 綠能自持不耗資源。</li>
          </ul>

          <h4>供電收入表</h4>
          <div class="payout-grid">
            <span
              v-for="row in payoutRows"
              :key="row.powered"
              class="payout-cell"
              :class="{ hl: row.powered === ui.payoutHighlight }"
            >
              {{ row.powered }} 城 → ${{ row.income }}
            </span>
          </div>
          <p class="hint">供電 0 城也有保底收入；邊際收入遞減——多供 1 城多賺多少，看相鄰兩格差。</p>
        </template>

        <!-- 終局 -->
        <template v-else-if="ui.rulesTab === 'end'">
          <ul>
            <li>擴建階段結束時，有人城市數達到<strong>終局門檻</strong>（見流程分頁的人數參數）→ 完成該回合的官僚結算後遊戲結束。</li>
            <li>勝者是最終結算<strong>能供電最多節點</strong>的玩家——不是城市最多者！</li>
            <li>平手依序比：剩餘金錢 → 城市數。</li>
          </ul>
          <p class="hint">衝城數觸發終局前，記得先備妥足夠的設施容量與燃料——終局回合的供電力才是勝負手。</p>
        </template>

        <!-- 關於 -->
        <template v-else-if="ui.rulesTab === 'about'">
          <h4>主題對照表</h4>
          <table class="rules-table">
            <thead><tr><th>《電力公司》原版</th><th>本作</th></tr></thead>
            <tbody>
              <tr v-for="[from, to] in RESKIN" :key="from">
                <td>{{ from }}</td>
                <td>{{ to }}</td>
              </tr>
            </tbody>
          </table>
          <p class="hint">
            本專案為非商業粉絲致敬作品，遊戲機制致敬 Friedemann Friese 設計的《Power Grid（Funkenschlag）》，
            與原設計師、2F-Spiele 及 Rio Grande Games 無任何隸屬、授權或合作關係；不使用原作素材，
            無任何商業行為。若權利人有任何疑慮，請與開發者聯繫，我們將立即配合處理。
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
