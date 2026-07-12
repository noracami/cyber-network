<script setup>
import { computed } from 'vue'
import { ICONS } from '../game/icons'

const props = defineProps({
  /** 圖示名（icons.js 的 key：hydro/thermal/waste/quantum/hybrid/self/fusion/bolt/city/credits） */
  name: { type: String, required: true },
  size: { type: [Number, String], default: 18 },
  /** 覆寫顏色（如反灰、單色場合）；預設用圖示專色 */
  color: { type: String, default: '' },
})

const icon = computed(() => ICONS[props.name])
</script>

<template>
  <svg
    v-if="icon"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    class="gicon"
    aria-hidden="true"
  >
    <path
      v-for="(p, index) in icon.paths"
      :key="index"
      :d="p.d"
      :fill="p.fill ? color || p.color || icon.color : 'none'"
      :stroke="p.stroke ? color || p.color || icon.color : 'none'"
      :stroke-width="p.w || 1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>
