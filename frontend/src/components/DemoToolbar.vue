<script setup>
import { SCENARIOS, applyScenario, scenario } from '../demo/demo'
</script>

<template>
  <div class="demo-bar">
    <span class="demo-tag">🧪 展示模式</span>
    <button
      v-for="item in SCENARIOS"
      :key="item.key"
      class="tab"
      :class="{ active: scenario === item.key }"
      @click="applyScenario(item.key)"
    >
      {{ item.label }}
    </button>
    <span class="hint">假資料渲染、動作不送出——玩家列電廠可點、頂欄可開規則彈窗</span>
  </div>
</template>
