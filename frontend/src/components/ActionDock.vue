<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { burnFeasible } from '../game/capacity'
import { cost as ladderCost } from '../game/ladder'
import { RESOURCE_META } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'
import PlantCard from './PlantCard.vue'

const room = useRoomStore()
const staticStore = useStaticStore()

const RESOURCES = Object.keys(RESOURCE_META)

const game = computed(() => room.game)
const phaseState = computed(() => game.value?.phase_state || {})
const me = computed(() => game.value?.players[room.selfId] || null)
const isPlayer = computed(() => me.value !== null)

// ── 競標 ──────────────────────────────
const bidding = computed(() => phaseState.value.bidding || null)
const myBidTurn = computed(() => bidding.value?.turn === room.selfId)
const discarding = computed(() => phaseState.value.pending_discard === room.selfId)
const justBought = computed(() => phaseState.value.bought?.[room.selfId])
const inQueue = computed(() => phaseState.value.queue?.includes(room.selfId))
const isNominator = computed(() => !bidding.value && phaseState.value.queue?.[0] === room.selfId)

const customBid = ref(0)
watch(bidding, (b) => {
  if (b) customBid.value = b.price + 1
})

// ── 資源採購 ──────────────────────────
const qty = reactive({ hydro: 0, thermal: 0, waste: 0, quantum: 0 })
const myResourceTurn = computed(
  () => game.value?.phase === 'resources' && phaseState.value.queue?.[0] === room.selfId
)

watch(
  () => game.value?.phase,
  () => {
    Object.assign(qty, { hydro: 0, thermal: 0, waste: 0, quantum: 0 })
    chosen.value = new Set()
  }
)

const priceOf = (resource) =>
  ladderCost(resource, game.value.resource_market[resource].count, qty[resource])

const totalPrice = computed(() =>
  RESOURCES.reduce((sum, resource) => sum + (priceOf(resource) ?? 0), 0)
)

function step(resource, delta) {
  const max = game.value.resource_market[resource].count
  qty[resource] = Math.min(Math.max(qty[resource] + delta, 0), max)
}

// ── 供電 ──────────────────────────────
/** @type {import('vue').Ref<Set<number>>} */
const chosen = ref(new Set())
const submitted = computed(() => phaseState.value.submitted?.includes(room.selfId))

function togglePlant(number) {
  const next = new Set(chosen.value)
  next.has(number) ? next.delete(number) : next.add(number)
  chosen.value = next
}

const chosenPlants = computed(() =>
  (me.value?.plants || []).filter((p) => chosen.value.has(p.number))
)
const feasible = computed(() => me.value && burnFeasible(me.value.resources, chosenPlants.value))
const powered = computed(() => {
  const capacity = chosenPlants.value.reduce((sum, p) => sum + p.powers, 0)
  return Math.min(capacity, me.value?.cities.length || 0)
})
const income = computed(() => staticStore.payout[Math.min(powered.value, 20)] ?? 0)

function submitPower() {
  room.gameAction('power_submit', { plants: [...chosen.value] })
}
</script>

<template>
  <div v-if="game" class="action-dock panel">
    <template v-if="!isPlayer">
      <p class="hint">👁 旁觀模式——你可以看牌局和聊天，但不能操作。</p>
    </template>

    <!-- 競標階段 -->
    <template v-else-if="game.phase === 'auction'">
      <div v-if="discarding" class="dock-section">
        <h3>設施超過上限，選一座棄置（不能棄剛買的 #{{ justBought }}）</h3>
        <div class="dock-cards">
          <PlantCard
            v-for="plant in me.plants.filter((p) => p.number !== justBought)"
            :key="plant.number"
            :number="plant.number"
            clickable
            @click="room.gameAction('auction_discard', { plant: plant.number })"
          />
        </div>
      </div>

      <div v-else-if="bidding" class="dock-section">
        <template v-if="myBidTurn">
          <h3>#{{ bidding.plant }} 競價中——現價 ${{ bidding.price }}（{{ room.nameOf(bidding.leader) }} 領先）</h3>
          <div class="dock-row">
            <button class="btn primary" @click="room.gameAction('auction_bid', { amount: bidding.price + 1 })">
              跟價 ${{ bidding.price + 1 }}
            </button>
            <input v-model.number="customBid" type="number" :min="bidding.price + 1" class="bid-input" />
            <button
              class="btn ghost"
              :disabled="customBid <= bidding.price"
              @click="room.gameAction('auction_bid', { amount: customBid })"
            >
              出價 ${{ customBid }}
            </button>
            <button class="btn danger" @click="room.gameAction('auction_fold')">放棄</button>
          </div>
        </template>
        <p v-else class="hint">
          #{{ bidding.plant }} 競價中（${{ bidding.price }}）——等待 {{ room.nameOf(bidding.turn) }} 出價…
        </p>
      </div>

      <div v-else-if="isNominator" class="dock-section dock-row">
        <p class="hint">從右側市場點選卡牌提名，或——</p>
        <button
          class="btn ghost"
          :disabled="game.round === 1"
          :title="game.round === 1 ? '第一回合必須買一座設施' : ''"
          @click="room.gameAction('auction_pass')"
        >
          本回合不買
        </button>
      </div>

      <p v-else-if="inQueue" class="hint">等待其他玩家提名…</p>
      <p v-else class="hint">你本回合的競標已結束。</p>
    </template>

    <!-- 採購資源階段 -->
    <template v-else-if="game.phase === 'resources'">
      <div v-if="myResourceTurn" class="dock-section">
        <h3>採購資源（反序輪到你）</h3>
        <div class="dock-row resource-steppers">
          <div v-for="(meta, resource) in RESOURCE_META" :key="resource" class="stepper">
            <span class="stepper-label">{{ meta.icon }} {{ meta.label }}</span>
            <button class="btn ghost sm" @click="step(resource, -1)">−</button>
            <span class="stepper-qty">{{ qty[resource] }}</span>
            <button class="btn ghost sm" @click="step(resource, 1)">＋</button>
            <span class="hint">${{ priceOf(resource) ?? '—' }}</span>
          </div>
        </div>
        <div class="dock-row">
          <strong>總價 ${{ totalPrice }}</strong>
          <button
            class="btn primary"
            :disabled="totalPrice > me.credits"
            @click="room.gameAction('resources_buy', { ...qty })"
          >
            購買
          </button>
          <button class="btn ghost" @click="room.gameAction('resources_buy', {})">跳過</button>
        </div>
      </div>
      <p v-else class="hint">等待 {{ room.nameOf(phaseState.queue?.[0]) }} 採購資源…</p>
    </template>

    <!-- 擴建階段 -->
    <template v-else-if="game.phase === 'building'">
      <div v-if="phaseState.queue?.[0] === room.selfId" class="dock-section dock-row">
        <p class="hint">點擊地圖上發亮的節點擴建（可連建多城），完成後——</p>
        <button class="btn primary" @click="room.gameAction('build_done')">結束擴建</button>
      </div>
      <p v-else class="hint">等待 {{ room.nameOf(phaseState.queue?.[0]) }} 擴建…</p>
    </template>

    <!-- 官僚階段 -->
    <template v-else-if="game.phase === 'bureaucracy'">
      <div v-if="!submitted" class="dock-section">
        <h3>選擇要啟動的設施</h3>
        <div class="dock-cards">
          <PlantCard
            v-for="plant in me.plants"
            :key="plant.number"
            :number="plant.number"
            clickable
            :selected="chosen.has(plant.number)"
            @click="togglePlant(plant.number)"
          />
          <p v-if="me.plants.length === 0" class="hint">你沒有任何設施。</p>
        </div>
        <div class="dock-row">
          <span :class="{ error: !feasible }">
            供電 {{ powered }} 節點 → 收入 ${{ income }}
            <template v-if="!feasible">（資源不足！）</template>
          </span>
          <button class="btn primary" :disabled="!feasible" @click="submitPower">送出供電計畫</button>
        </div>
      </div>
      <p v-else class="hint">已送出，等待其他玩家…</p>
    </template>
  </div>
</template>
