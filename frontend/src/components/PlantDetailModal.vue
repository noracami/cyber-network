<script setup>
import { computed } from 'vue'
import { TYPE_META } from '../game/text'
import { useStaticStore } from '../stores/staticData'
import { useUiStore } from '../stores/ui'
import GameIcon from './GameIcon.vue'

const ui = useUiStore()
const staticStore = useStaticStore()

const plant = computed(() =>
  ui.detailPlant != null ? staticStore.plantsByNumber.get(ui.detailPlant) : null
)
const meta = computed(() => (plant.value ? TYPE_META[plant.value.type] : null))
</script>

<template>
  <div v-if="plant" class="modal-mask" @click.self="ui.closePlant()">
    <div class="modal-box plant-detail">
      <div class="pd-head">
        <span class="pd-number">#{{ plant.number }}</span>
        <span class="pd-name">{{ plant.name }}</span>
        <button class="modal-close" @click="ui.closePlant()">✕</button>
      </div>
      <dl class="pd-stats">
        <dt>類型</dt>
        <dd><GameIcon :name="plant.type" :size="16" /> {{ meta.label }}</dd>
        <dt>燃料需求</dt>
        <dd>
          <template v-if="plant.fuel > 0"><GameIcon :name="plant.type" :size="14" /> ×{{ plant.fuel }}<span v-if="plant.type === 'hybrid'" class="hint">（水力／火力可任意混搭）</span></template>
          <template v-else>免燃料</template>
        </dd>
        <dt>供電</dt>
        <dd><GameIcon name="bolt" :size="14" /> {{ plant.powers }} 節點</dd>
        <dt v-if="plant.fuel > 0">儲存容量</dt>
        <dd v-if="plant.fuel > 0">{{ plant.fuel * 2 }}（需求 ×2，計入你的總儲存上限）</dd>
      </dl>
    </div>
  </div>
</template>
