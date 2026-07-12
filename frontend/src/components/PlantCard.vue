<script setup>
import { computed } from 'vue'
import { cardTraces } from '../game/cardArt'
import { TYPE_META } from '../game/text'
import { useStaticStore } from '../stores/staticData'
import GameIcon from './GameIcon.vue'

const props = defineProps({
  /** 卡號，或字串 "step3" */
  number: { type: [Number, String], required: true },
  clickable: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
  dimmed: { type: Boolean, default: false },
})

const staticStore = useStaticStore()

const plant = computed(() =>
  typeof props.number === 'number' ? staticStore.plantsByNumber.get(props.number) : null
)
const meta = computed(() => (plant.value ? TYPE_META[plant.value.type] : null))
const art = computed(() => (plant.value ? cardTraces(plant.value.number) : null))

/** 類型色帶；混合廠用水火漸層 */
const band = computed(() => {
  if (!plant.value) return ''
  if (plant.value.type === 'hybrid') return 'linear-gradient(180deg, #4da6ff, #fb923c)'
  return meta.value?.color || 'var(--border)'
})

/** 幾何紋顏色；混合廠雙色交錯 */
function traceColor(index) {
  if (plant.value?.type === 'hybrid') return index % 2 ? '#fb923c' : '#4da6ff'
  return meta.value?.color || '#37e6d4'
}
</script>

<template>
  <div
    class="plant-card"
    :class="{ clickable, selected, dimmed, step3: number === 'step3' }"
  >
    <template v-if="plant">
      <span class="pc-band" :style="{ background: band }"></span>
      <svg
        class="pc-art"
        :viewBox="`0 0 ${art.w} ${art.h}`"
        preserveAspectRatio="none"
        aria-hidden="true"
      >
        <path
          v-for="(d, index) in art.paths"
          :key="index"
          :d="d"
          fill="none"
          :stroke="traceColor(index)"
          stroke-width="1.1"
          opacity="0.18"
        />
        <circle
          v-for="(dot, index) in art.dots"
          :key="'d' + index"
          :cx="dot.x"
          :cy="dot.y"
          r="1.5"
          :fill="traceColor(index)"
          opacity="0.3"
        />
      </svg>
      <div class="pc-head">
        <span class="pc-number">{{ plant.number }}</span>
        <GameIcon :name="plant.type" :size="20" />
      </div>
      <div class="pc-name">{{ plant.name }}</div>
      <div class="pc-stats">
        <template v-if="plant.fuel > 0">
          <GameIcon :name="plant.type" :size="11" /><span>×{{ plant.fuel }}</span>
        </template>
        <span v-else>免燃料</span>
        <span class="pc-arrow">→</span>
        <GameIcon name="bolt" :size="11" /><span>{{ plant.powers }}</span>
      </div>
    </template>
    <template v-else>
      <div class="pc-step3">STEP<br />3</div>
    </template>
  </div>
</template>
