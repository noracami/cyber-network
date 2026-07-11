<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { MapBoard } from '../game/board'
import { buildAdjacency, minToll } from '../game/dijkstra'
import { seatColor } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'

const room = useRoomStore()
const staticStore = useStaticStore()

const host = ref(/** @type {HTMLElement | null} */ (null))
const hover = ref(/** @type {{name: string, cost: number | null, x: number, y: number} | null} */ (null))
const pendingBuild = ref(/** @type {{id: string, name: string, cost: number} | null} */ (null))

/** @type {MapBoard | null} */
let board = null

const adjacency = computed(() =>
  staticStore.loaded && room.game
    ? buildAdjacency(staticStore.map, room.game.active_regions)
    : null
)

const myBuildTurn = computed(
  () => room.game?.phase === 'building' && room.game.phase_state?.queue?.[0] === room.selfId
)

/** 擴建成本預覽；不可建回 null。成交價以後端為準。 */
function buildCost(cityId) {
  const game = room.game
  if (!myBuildTurn.value || !adjacency.value || !game) return null
  const owners = game.city_owners[cityId] || []
  if (owners.includes(room.selfId) || owners.length >= game.step) return null
  const toll = minToll(adjacency.value, game.players[room.selfId]?.cities || [], cityId)
  if (toll == null) return null
  return toll + staticStore.rules.city_slot_costs[owners.length]
}

function redraw() {
  if (!board || !staticStore.loaded || !room.game) return
  board.update({
    map: staticStore.map,
    game: room.game,
    colorOf: (id) => seatColor(room.seats, id),
    buildableCost: (cityId) => buildCost(cityId),
    onCityTap: (cityId) => {
      const cost = buildCost(cityId)
      if (cost == null) return
      pendingBuild.value = { id: cityId, name: staticStore.cityName(cityId), cost }
    },
    onHover: (cityId, x, y) => {
      if (!cityId) {
        hover.value = null
        return
      }
      hover.value = { name: staticStore.cityName(cityId), cost: buildCost(cityId), x, y }
    },
  })
}

async function confirmBuild() {
  if (!pendingBuild.value) return
  await room.gameAction('build', { city: pendingBuild.value.id })
  pendingBuild.value = null
}

function resetMapView() {
  board?.resetView()
}

onMounted(async () => {
  board = new MapBoard()
  await board.init(host.value)
  redraw()
})

onBeforeUnmount(() => board?.destroy())

watch(() => room.game, redraw)
watch(() => staticStore.loaded, redraw)
</script>

<template>
  <div class="map-wrap panel">
    <div ref="host" class="map-canvas"></div>

    <button class="map-reset btn ghost sm" title="回到全圖" @click="resetMapView">⤢ 全圖</button>

    <div
      v-if="hover"
      class="map-tooltip"
      :style="{ left: hover.x + 14 + 'px', top: hover.y + 14 + 'px' }"
    >
      {{ hover.name }}<template v-if="hover.cost != null">・約 ${{ hover.cost }}</template>
    </div>

    <div v-if="pendingBuild" class="map-confirm">
      <p>
        佔據 <strong>{{ pendingBuild.name }}</strong>（預估 ${{ pendingBuild.cost }}）？
      </p>
      <div class="dock-row">
        <button class="btn primary" @click="confirmBuild">擴建</button>
        <button class="btn ghost" @click="pendingBuild = null">取消</button>
      </div>
    </div>
  </div>
</template>
