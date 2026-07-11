<script setup>
import { computed } from 'vue'
import { TYPE_META } from '../game/text'
import { useStaticStore } from '../stores/staticData'

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
</script>

<template>
  <div
    class="plant-card"
    :class="{ clickable, selected, dimmed, step3: number === 'step3' }"
  >
    <template v-if="plant">
      <div class="pc-head">
        <span class="pc-number">{{ plant.number }}</span>
        <span class="pc-type">{{ meta.icon }}</span>
      </div>
      <div class="pc-name">{{ plant.name }}</div>
      <div class="pc-stats">
        <span v-if="plant.fuel > 0">{{ meta.icon }}×{{ plant.fuel }}</span>
        <span v-else>免燃料</span>
        → ⚡{{ plant.powers }}
      </div>
    </template>
    <template v-else>
      <div class="pc-step3">STEP<br />3</div>
    </template>
  </div>
</template>
