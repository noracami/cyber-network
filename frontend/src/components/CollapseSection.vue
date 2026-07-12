<script setup>
import { ref } from 'vue'

defineProps({
  title: { type: String, required: true },
})

// 手機（R3）：面板預設收合成標題列；桌機此元件完全透明（display: contents）
const isMobile = window.matchMedia('(max-width: 700px)').matches
const open = ref(!isMobile)
</script>

<template>
  <div class="collapse-section">
    <button v-if="isMobile" class="collapse-head" @click="open = !open">
      <span>{{ title }}</span>
      <span class="collapse-arrow">{{ open ? '▾' : '▸' }}</span>
    </button>
    <div v-show="!isMobile || open" class="collapse-body">
      <slot />
    </div>
  </div>
</template>
