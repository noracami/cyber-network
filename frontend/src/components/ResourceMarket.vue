<script setup>
import { computed } from 'vue'
import { cost, ladder } from '../game/ladder'
import { RESOURCE_META } from '../game/text'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()
const market = computed(() => room.game?.resource_market || null)

/**
 * 依價位分組成格位圖。價梯不變量：存量永遠填在最貴端連續格位，
 * 因此索引 ≥ (總格數 − 存量) 的格子即為「有貨」。
 * @param {string} resource
 * @returns {{price: number, slots: boolean[]}[]}
 */
function groupsOf(resource) {
  const steps = ladder(resource)
  const count = market.value?.[resource]?.count ?? 0
  const firstFilled = steps.length - count
  /** @type {{price: number, slots: boolean[]}[]} */
  const groups = []
  steps.forEach((price, index) => {
    const filled = index >= firstFilled
    const last = groups[groups.length - 1]
    if (last && last.price === price) last.slots.push(filled)
    else groups.push({ price, slots: [filled] })
  })
  return groups
}

/** @param {string} resource */
const nextPrice = (resource) => cost(resource, market.value?.[resource]?.count ?? 0, 1)
</script>

<template>
  <div v-if="market" class="resource-market panel">
    <h3>資源市場 <span class="hint">單價看存量：越買越貴、補貨變便宜</span></h3>
    <div v-for="(meta, resource) in RESOURCE_META" :key="resource" class="rm-row">
      <span class="rm-icon" :title="meta.label">{{ meta.icon }}</span>
      <div class="rm-ladder">
        <div v-for="group in groupsOf(resource)" :key="group.price" class="rm-group">
          <div class="rm-slots">
            <span
              v-for="(filled, index) in group.slots"
              :key="index"
              class="rm-slot"
              :class="{ filled }"
            ></span>
          </div>
          <span class="rm-price">{{ group.price }}</span>
        </div>
      </div>
      <span class="rm-next hint">
        <template v-if="nextPrice(resource) != null">×{{ market[resource].count }}・${{ nextPrice(resource) }}</template>
        <template v-else>售罄</template>
      </span>
    </div>
  </div>
</template>
