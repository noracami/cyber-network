<script setup>
import { SCENARIOS, applyScenario, fireFx, scenario } from '../demo/demo'
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
    <span class="demo-tag">▶</span>
    <button class="tab" @click="fireFx('built')">蓋城</button>
    <button class="tab" @click="fireFx('powered')">供電</button>
    <button class="tab" @click="fireFx('step')">Step</button>
    <span class="hint">假資料渲染、動作不送出</span>
  </div>
</template>
