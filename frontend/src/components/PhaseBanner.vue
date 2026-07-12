<script setup>
import { computed } from 'vue'
import { PHASE_TEXT } from '../game/text'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

/** 回合內的階段順序（順位計算是自動的，不佔一格） */
const PHASES = ['auction', 'resources', 'building', 'bureaucracy']

const STEP_TIP = `全局大階段，影響建城與補貨：
Step 1｜每座城市只開放 1 個進駐位
Step 2｜有人蓋到觸發城數後開始——城市開放第 2 位
Step 3｜Step 3 卡現身後開始——城市開放第 3 位、設施市場縮為 6 張全部可競標
（每回合資源補貨量依 Step 查表，詳見規則說明）`

const game = computed(() => room.game)
const phaseState = computed(() => game.value?.phase_state || {})

const statusLine = computed(() => {
  const g = game.value
  if (!g) return ''
  const nameOf = room.nameOf
  const ps = phaseState.value

  if (g.phase === 'auction') {
    if (ps.pending_discard) return `${nameOf(ps.pending_discard)} 正在棄置設施…`
    if (ps.bidding) {
      const b = ps.bidding
      return `#${b.plant} 競價中：現價 $${b.price}（${nameOf(b.leader)} 領先）— 輪到 ${nameOf(b.turn)}`
    }
    if (ps.queue?.length) return `輪到 ${nameOf(ps.queue[0])} 提名設施`
  }
  if (g.phase === 'resources' && ps.queue?.length) return `輪到 ${nameOf(ps.queue[0])} 採購資源`
  if (g.phase === 'building' && ps.queue?.length) return `輪到 ${nameOf(ps.queue[0])} 擴建網路`
  if (g.phase === 'bureaucracy') {
    const pending = Object.keys(g.players).filter((id) => !ps.submitted?.includes(id))
    return pending.length ? `等待供電計畫：${pending.map(nameOf).join('、')}` : '結算中…'
  }
  return ''
})

const isMyTurn = computed(() => {
  const ps = phaseState.value
  return (
    ps.pending_discard === room.selfId ||
    ps.bidding?.turn === room.selfId ||
    (!ps.bidding && ps.queue?.[0] === room.selfId)
  )
})
</script>

<template>
  <div v-if="game" class="phase-banner" :class="{ 'my-turn': isMyTurn }">
    <span class="pb-round">第 {{ game.round }} 回合</span>
    <span class="pb-step" :title="STEP_TIP">STEP {{ game.step }}</span>
    <span class="pb-phases">
      <template v-for="(phase, index) in PHASES" :key="phase">
        <span v-if="index > 0" class="pb-arrow">›</span>
        <span class="pb-phase" :class="{ active: game.phase === phase }">{{ PHASE_TEXT[phase] }}</span>
      </template>
    </span>
    <span v-if="game.final_round" class="pb-final">🏁 終局回合</span>
    <span class="pb-status">{{ statusLine }}</span>
  </div>
</template>
