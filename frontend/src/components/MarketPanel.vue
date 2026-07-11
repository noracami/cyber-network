<script setup>
import { computed, ref } from 'vue'
import { useRoomStore } from '../stores/room'
import PlantCard from './PlantCard.vue'

const room = useRoomStore()

const game = computed(() => room.game)
const phaseState = computed(() => game.value?.phase_state || {})

const canNominate = computed(
  () =>
    game.value?.phase === 'auction' &&
    !phaseState.value.bidding &&
    !phaseState.value.pending_discard &&
    phaseState.value.queue?.[0] === room.selfId
)

/** @type {import('vue').Ref<number | null>} */
const nominating = ref(null)
const openingBid = ref(0)

function clickCard(number) {
  if (!canNominate.value || typeof number !== 'number') return
  nominating.value = number
  openingBid.value = number
}

async function confirmNominate() {
  if (nominating.value == null) return
  await room.gameAction('auction_choose', { plant: nominating.value, bid: openingBid.value })
  nominating.value = null
}
</script>

<template>
  <div v-if="game" class="market panel">
    <h3>設施市場 <span class="hint">牌庫 {{ game.deck_count }}</span></h3>

    <div class="market-row">
      <PlantCard
        v-for="number in game.market.actual"
        :key="number"
        :number="number"
        :clickable="canNominate"
        :selected="nominating === number"
        @click="clickCard(number)"
      />
    </div>

    <div v-if="game.market.future.length" class="market-row future">
      <PlantCard v-for="number in game.market.future" :key="number" :number="number" dimmed />
    </div>

    <div v-if="nominating != null" class="nominate-form">
      <label>
        起標價
        <input v-model.number="openingBid" type="number" :min="nominating" max="999" />
      </label>
      <button class="btn primary" :disabled="openingBid < nominating" @click="confirmNominate">
        提名 #{{ nominating }}
      </button>
      <button class="btn ghost" @click="nominating = null">取消</button>
    </div>
    <p v-else-if="canNominate" class="hint">輪到你——點選上排卡牌提名競標。</p>
  </div>
</template>
