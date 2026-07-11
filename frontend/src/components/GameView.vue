<script setup>
import { computed } from 'vue'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

const PHASE_TEXT = {
  auction: '競標設施',
  resources: '採購資源',
  building: '擴建網路',
  bureaucracy: '結算供電',
}

const game = computed(() => room.game)
const phaseText = computed(() => PHASE_TEXT[game.value?.phase] || game.value?.phase)
</script>

<template>
  <div v-if="game" class="game-placeholder">
    <h2>
      遊戲進行中
      <span class="hint">第 {{ game.round }} 回合・Step {{ game.step }}・{{ phaseText }}</span>
    </h2>

    <div class="panel">
      <h3>順位</h3>
      <ol class="turn-order">
        <li v-for="id in game.turn_order" :key="id" :class="{ self: id === room.selfId }">
          {{ room.nameOf(id) }}
          <span class="hint">
            💰{{ game.players[id]?.credits }}・🏙{{ game.players[id]?.cities.length }}
          </span>
        </li>
      </ol>
    </div>

    <div class="panel">
      <h3>設施市場</h3>
      <p>
        現行：<code>{{ game.market.actual.join('、') }}</code>
        <template v-if="game.market.future.length">
          ／未來：<code>{{ game.market.future.join('、') }}</code>
        </template>
        ・牌庫 {{ game.deck_count }} 張
      </p>
      <h3>資源市場</h3>
      <p>
        💧 {{ game.resource_market.hydro.count }}（${{ game.resource_market.hydro.cheapest ?? '—' }}）
        🔥 {{ game.resource_market.thermal.count }}（${{ game.resource_market.thermal.cheapest ?? '—' }}）
        ♻️ {{ game.resource_market.waste.count }}（${{ game.resource_market.waste.cheapest ?? '—' }}）
        🧠 {{ game.resource_market.quantum.count }}（${{ game.resource_market.quantum.cheapest ?? '—' }}）
      </p>
    </div>

    <p class="hint">🚧 完整盤面（地圖、卡牌、操作介面）在 M5 施工中——目前為狀態檢視模式。</p>
  </div>
</template>
