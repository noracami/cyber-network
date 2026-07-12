<script setup>
import { computed } from 'vue'
import { capsOf } from '../game/capacity'
import { RESOURCE_META, seatColor, TYPE_META } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useUiStore } from '../stores/ui'

const room = useRoomStore()
const ui = useUiStore()

const players = computed(() => {
  const game = room.game
  if (!game) return []
  return game.turn_order.map((id) => ({
    id,
    name: room.nameOf(id),
    color: seatColor(room.seats, id),
    storage: storageRows(game.players[id]),
    ...game.players[id],
  }))
})

/**
 * 儲存凹槽模型（v1.2）：凹槽數＝容量、格內符號＝持有的資源。
 * 專屬容量一列一類型；混合容量另列，裝水力／火力超出專屬容量的溢出
 * （與引擎的總量驗證等價，見 engine-design §6.3）。
 * @returns {{key: string, label: string, slots: (string|null)[]}[]}
 */
function storageRows(player) {
  const caps = capsOf(player.plants)
  const res = player.resources
  const rows = []

  for (const type of ['hydro', 'thermal', 'waste', 'quantum']) {
    if (caps[type] === 0) continue
    const filled = Math.min(res[type], caps[type])
    rows.push({
      key: type,
      label: RESOURCE_META[type].icon,
      slots: Array.from({ length: caps[type] }, (_, i) => (i < filled ? RESOURCE_META[type].icon : null)),
    })
  }

  if (caps.hybrid > 0) {
    const overflow = [
      ...Array(Math.max(0, res.hydro - caps.hydro)).fill(RESOURCE_META.hydro.icon),
      ...Array(Math.max(0, res.thermal - caps.thermal)).fill(RESOURCE_META.thermal.icon),
    ]
    rows.push({
      key: 'hybrid',
      label: '💧🔥',
      slots: Array.from({ length: caps.hybrid }, (_, i) => overflow[i] || null),
    })
  }

  return rows
}
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
        <button
          v-for="plant in player.plants"
          :key="plant.number"
          class="mini-plant"
          title="點擊查看設施詳情"
          @click="ui.showPlant(plant.number)"
        >
          <template v-if="player.id === room.selfId">
            #{{ plant.number }}{{ TYPE_META[plant.type]?.icon }}<template v-if="plant.fuel > 0">×{{ plant.fuel }}</template>⚡{{ plant.powers }}
          </template>
          <template v-else>#{{ plant.number }}{{ TYPE_META[plant.type]?.icon }}</template>
        </button>
      </div>
      <div v-for="row in player.storage" :key="row.key" class="pc-row storage-row">
        <span class="storage-label">{{ row.label }}</span>
        <span
          v-for="(slot, index) in row.slots"
          :key="index"
          class="res-slot"
          :class="{ filled: slot }"
        >{{ slot || '' }}</span>
      </div>
    </div>
  </div>
</template>
