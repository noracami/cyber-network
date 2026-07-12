<script setup>
import { computed } from 'vue'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'
import ActionDock from './ActionDock.vue'
import CollapseSection from './CollapseSection.vue'
import GameLog from './GameLog.vue'
import MapBoard from './MapBoard.vue'
import MarketPanel from './MarketPanel.vue'
import PhaseBanner from './PhaseBanner.vue'
import ResourceMarket from './ResourceMarket.vue'

const room = useRoomStore()
const staticStore = useStaticStore()
const ready = computed(() => staticStore.loaded)
// 當前階段的主面板嵌進操作面板（v1.2/v1.3），下方面板列不重複顯示
const marketInDock = computed(() => room.game?.phase === 'resources')
const plantMarketInDock = computed(() => room.game?.phase === 'auction')
</script>

<template>
  <p v-if="staticStore.failed" class="error">靜態數據載入失敗——請確認後端 /api/static 可連線後重整。</p>
  <p v-else-if="!ready" class="hint">載入遊戲數據中…</p>

  <div v-else class="game">
    <PhaseBanner />
    <ActionDock />
    <MapBoard />
    <!-- 手機（R3）：市場／日誌收合成標題列，桌機不變 -->
    <div class="panel-row">
      <CollapseSection v-if="!plantMarketInDock" title="🏭 設施市場">
        <MarketPanel />
      </CollapseSection>
      <CollapseSection v-if="!marketInDock" title="⛽ 資源市場">
        <ResourceMarket />
      </CollapseSection>
      <CollapseSection title="📜 事件紀錄">
        <GameLog />
      </CollapseSection>
    </div>
  </div>
</template>
