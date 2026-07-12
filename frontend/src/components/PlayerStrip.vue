<script setup>
import { computed, ref, watch } from 'vue'
import { seatColor } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useUiStore } from '../stores/ui'
import GameIcon from './GameIcon.vue'
import StorageSockets from './StorageSockets.vue'

const room = useRoomStore()
const ui = useUiStore()

/** 剛得標的設施卡號——標籤閃光 1.3 秒（A3） */
const flashing = ref(new Set())
watch(
  () => room.lastEvents,
  (events) => {
    for (const event of events || []) {
      if (event.type !== 'plant_bought') continue
      flashing.value = new Set([...flashing.value, event.plant])
      setTimeout(() => {
        const next = new Set(flashing.value)
        next.delete(event.plant)
        flashing.value = next
      }, 1400)
    }
  }
)

const players = computed(() => {
  const game = room.game
  if (!game) return []
  return game.turn_order.map((id) => ({
    id,
    name: room.nameOf(id),
    color: seatColor(room.seats, id),
    ...game.players[id],
  }))
})
</script>

<template>
  <div class="player-strip">
    <div
      v-for="player in players"
      :key="player.id"
      class="player-chip"
      :class="{ self: player.id === room.selfId }"
    >
      <div class="pc-row">
        <span class="pc-dot" :style="{ background: player.color }"></span>
        <strong>{{ player.name }}</strong>
        <span class="hint stat-pair">
          <GameIcon name="credits" :size="14" />{{ player.credits }}
          <GameIcon name="city" :size="14" />{{ player.cities.length }}
        </span>
      </div>
      <div class="pc-row hint">
        <button
          v-for="plant in player.plants"
          :key="plant.number"
          class="mini-plant"
          :class="{ flash: flashing.has(plant.number) }"
          title="點擊查看設施詳情"
          @click="ui.showPlant(plant.number)"
        >
          #{{ plant.number }}
          <GameIcon :name="plant.type" :size="12" />
          <template v-if="player.id === room.selfId">
            <template v-if="plant.fuel > 0">×{{ plant.fuel }}</template>
            <GameIcon name="bolt" :size="11" />{{ plant.powers }}
          </template>
        </button>
      </div>
      <StorageSockets :plants="player.plants" :resources="player.resources" />
    </div>
  </div>
</template>
