<script setup>
import { computed } from 'vue'
import { RESOURCE_META } from '../game/text'
import { useRoomStore } from '../stores/room'
import GameIcon from './GameIcon.vue'
import ResourceLadder from './ResourceLadder.vue'

defineProps({
  /** 嵌在操作面板內（採購階段給等待中玩家看），不套獨立 panel 外框 */
  embedded: { type: Boolean, default: false },
})

const room = useRoomStore()
const market = computed(() => room.game?.resource_market || null)
</script>

<template>
  <div v-if="market" class="resource-market" :class="embedded ? 'embedded' : 'panel'">
    <h3>資源市場 <span class="hint">單價看存量：越買越貴、補貨變便宜</span></h3>
    <div v-for="(meta, resource) in RESOURCE_META" :key="resource" class="rm-row">
      <span class="rm-icon" :title="meta.label"><GameIcon :name="resource" :size="20" /></span>
      <ResourceLadder :resource="resource" :count="market[resource].count" />
    </div>
  </div>
</template>
