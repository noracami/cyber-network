<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { MapBoard } from '../game/board'
import { buildAdjacency, minToll, minTollPath } from '../game/dijkstra'
import { gridLayout } from '../game/gridLayout'
import { seatColor } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useSettingsStore } from '../stores/settings'
import { useStaticStore } from '../stores/staticData'

const room = useRoomStore()
const settings = useSettingsStore()
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

/** 網格佈局（純顯示層）；地理模式為 null */
const layout = computed(() =>
  settings.mapLayout === 'grid' && staticStore.loaded ? gridLayout(staticStore.map) : null
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
    layout: layout.value,
    colorOf: (id) => seatColor(room.seats, id),
    buildableCost: (cityId) => buildCost(cityId),
    onCityTap: (cityId) => {
      const cost = buildCost(cityId)
      if (cost == null) return
      pendingBuild.value = { id: cityId, name: staticStore.cityName(cityId), cost }
      // 確認框開啟期間：路徑連線動畫＋沿線過路費放大＋目的地進場費
      const myCities = room.game?.players[room.selfId]?.cities || []
      const { path } = minTollPath(adjacency.value, myCities, cityId)
      const owners = room.game?.city_owners[cityId] || []
      const entryFee = staticStore.rules.city_slot_costs[owners.length]
      board?.showRoute(path, seatColor(room.seats, room.selfId), cityId, entryFee)
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
  board.setNav(settings.mapNav)
  redraw()
})

onBeforeUnmount(() => board?.destroy())

watch(() => room.game, redraw)
watch(() => staticStore.loaded, redraw)
watch(layout, redraw)
// 事件動畫（A3）：redraw 先吃新狀態，再播放這批事件的特效
watch(
  () => room.lastEvents,
  (events) => board?.playEvents(events)
)
watch(
  () => settings.mapNav,
  (enabled) => board?.setNav(enabled)
)
// 確認框收掉（擴建／取消／換狀態）→ 路徑動畫跟著收
watch(pendingBuild, (pending) => {
  if (!pending) board?.clearRoute()
})
</script>

<template>
  <div class="map-wrap panel">
    <div ref="host" class="map-canvas"></div>

    <div class="map-tools">
      <button
        class="btn ghost sm"
        :title="settings.mapLayout === 'grid' ? '切回地理位置佈局' : '切換垂直水平線路佈局'"
        @click="settings.toggleMapLayout()"
      >
        {{ settings.mapLayout === 'grid' ? '🌐 地理' : '⊞ 網格' }}
      </button>
      <button
        class="btn ghost sm"
        :class="{ 'nav-on': settings.mapNav }"
        :title="settings.mapNav ? '鎖定地圖（回到全覽）' : '啟用拖曳平移與縮放'"
        @click="settings.toggleMapNav()"
      >
        🔍 縮放{{ settings.mapNav ? '：開' : '：關' }}
      </button>
      <button v-if="settings.mapNav" class="btn ghost sm" title="回到全圖" @click="resetMapView">⤢ 全圖</button>
    </div>

    <div
      v-if="hover"
      class="map-tooltip"
      :style="{ left: hover.x + 14 + 'px', top: hover.y + 14 + 'px' }"
    >
      {{ hover.name }}<template v-if="hover.cost != null">・${{ hover.cost }}</template>
    </div>

    <div v-if="pendingBuild" class="map-confirm">
      <p>
        佔據 <strong>{{ pendingBuild.name }}</strong>（${{ pendingBuild.cost }}）？
      </p>
      <div class="dock-row">
        <button class="btn primary" @click="confirmBuild">擴建</button>
        <button class="btn ghost" @click="pendingBuild = null">取消</button>
      </div>
    </div>
  </div>
</template>
