<script setup>
import { computed } from 'vue'
import { PHASE_TEXT } from '../game/text'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

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
    <span class="pb-step">STEP {{ game.step }}</span>
    <span class="pb-phase">{{ PHASE_TEXT[game.phase] || game.phase }}</span>
    <span v-if="game.final_round" class="pb-final">🏁 終局回合</span>
    <span class="pb-status">{{ statusLine }}</span>
  </div>
</template>
