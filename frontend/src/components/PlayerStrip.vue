<script setup>
import { computed } from 'vue'
import { RESOURCE_META, seatColor, TYPE_META } from '../game/text'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

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
        <span class="hint">💰{{ player.credits }}・🏙{{ player.cities.length }}</span>
      </div>
      <div class="pc-row hint">
        <span v-for="plant in player.plants" :key="plant.number" class="mini-plant">
          #{{ plant.number }}{{ TYPE_META[plant.type]?.icon }}
        </span>
      </div>
      <div class="pc-row hint">
        <template v-for="(meta, resource) in RESOURCE_META" :key="resource">
          <span v-if="player.resources[resource] > 0" class="mini-res">
            {{ meta.icon }}{{ player.resources[resource] }}
          </span>
        </template>
      </div>
    </div>
  </div>
</template>
