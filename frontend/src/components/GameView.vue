<script setup>
import { computed } from 'vue'
import { useStaticStore } from '../stores/staticData'
import ActionDock from './ActionDock.vue'
import GameLog from './GameLog.vue'
import MapBoard from './MapBoard.vue'
import MarketPanel from './MarketPanel.vue'
import PhaseBanner from './PhaseBanner.vue'
import PlayerStrip from './PlayerStrip.vue'
import ResourceMarket from './ResourceMarket.vue'

const staticStore = useStaticStore()
const ready = computed(() => staticStore.loaded)
</script>

<template>
  <p v-if="staticStore.failed" class="error">靜態數據載入失敗——請確認後端 /api/static 可連線後重整。</p>
  <p v-else-if="!ready" class="hint">載入遊戲數據中…</p>

  <div v-else class="game">
    <PhaseBanner />
    <MapBoard />
    <ActionDock />
    <PlayerStrip />
    <div class="panel-row">
      <MarketPanel />
      <ResourceMarket />
      <GameLog />
    </div>
  </div>
</template>
