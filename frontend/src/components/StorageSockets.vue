<script setup>
import { computed } from 'vue'
import { capsOf } from '../game/capacity'
import GameIcon from './GameIcon.vue'

const props = defineProps({
  /** 玩家的設施清單（{type, fuel} 陣列） */
  plants: { type: Array, required: true },
  /** 玩家持有資源 {hydro, thermal, waste, quantum} */
  resources: { type: Object, required: true },
})

/**
 * 儲存凹槽模型：凹槽數＝容量、格內圖示＝持有的資源。
 * 專屬容量一列一類型；混合容量另列，裝水力／火力超出專屬容量的溢出
 * （與引擎的總量驗證等價，見 engine-design §6.3）。
 */
const rows = computed(() => {
  const caps = capsOf(props.plants)
  const res = props.resources
  const result = []

  for (const type of ['hydro', 'thermal', 'waste', 'quantum']) {
    if (caps[type] === 0) continue
    const filled = Math.min(res[type], caps[type])
    result.push({
      key: type,
      slots: Array.from({ length: caps[type] }, (_, i) => (i < filled ? type : null)),
    })
  }

  if (caps.hybrid > 0) {
    const overflow = [
      ...Array(Math.max(0, res.hydro - caps.hydro)).fill('hydro'),
      ...Array(Math.max(0, res.thermal - caps.thermal)).fill('thermal'),
    ]
    result.push({
      key: 'hybrid',
      slots: Array.from({ length: caps.hybrid }, (_, i) => overflow[i] || null),
    })
  }

  return result
})
</script>

<template>
  <div>
    <div v-for="row in rows" :key="row.key" class="pc-row storage-row">
      <span class="storage-label"><GameIcon :name="row.key" :size="14" /></span>
      <span
        v-for="(slot, index) in row.slots"
        :key="index"
        class="res-slot"
        :class="{ filled: slot }"
      >
        <GameIcon v-if="slot" :name="slot" :size="13" />
      </span>
    </div>
  </div>
</template>
