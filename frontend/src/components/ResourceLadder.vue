<script setup>
import { computed } from 'vue'
import { ladder } from '../game/ladder'
import { RESOURCE_META } from '../game/text'

const props = defineProps({
  /** 資源 id（hydro/thermal/waste/quantum） */
  resource: { type: String, required: true },
  /** 市場現量 */
  count: { type: Number, required: true },
  /** 採購預覽數量：存量區最便宜的 n 格顯示黃色 −單價 */
  taking: { type: Number, default: 0 },
})

const icon = computed(() => RESOURCE_META[props.resource]?.icon)

/**
 * 依價位分組成格位圖。價梯不變量：存量永遠填在最貴端連續格位；
 * 採購從最便宜的存量格買起 → taking = 存量區最前（最便宜）的 n 格。
 */
const groups = computed(() => {
  const steps = ladder(props.resource)
  const firstFilled = steps.length - props.count
  /** @type {{price: number, slots: string[]}[]} */
  const result = []
  steps.forEach((price, index) => {
    const state =
      index < firstFilled ? 'empty' : index < firstFilled + props.taking ? 'taking' : 'filled'
    const last = result[result.length - 1]
    if (last && last.price === price) last.slots.push(state)
    else result.push({ price, slots: [state] })
  })
  return result
})
</script>

<template>
  <div class="rm-ladder">
    <div v-for="group in groups" :key="group.price" class="rm-group">
      <div class="rm-slots">
        <span
          v-for="(state, index) in group.slots"
          :key="index"
          class="rm-socket"
          :class="state"
        >
          <template v-if="state === 'filled'">{{ icon }}</template>
          <template v-else-if="state === 'taking'">-{{ group.price }}</template>
        </span>
      </div>
      <span class="rm-price">{{ group.price }}</span>
    </div>
  </div>
</template>
