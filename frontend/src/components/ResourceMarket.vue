<script setup>
import { computed } from 'vue'
import { cost, ladder } from '../game/ladder'
import { RESOURCE_META } from '../game/text'
import { useRoomStore } from '../stores/room'

const props = defineProps({
  /** 採購預覽（v1.2）：各資源將購買的數量——要被買走的格位標成 taking */
  pending: { type: Object, default: null },
  /** 嵌在操作面板內（採購階段），不套獨立 panel 外框 */
  embedded: { type: Boolean, default: false },
})

const room = useRoomStore()
const market = computed(() => room.game?.resource_market || null)

/** @param {string} resource */
const takingOf = (resource) => props.pending?.[resource] || 0

/**
 * 依價位分組成格位圖。價梯不變量：存量永遠填在最貴端連續格位；
 * 採購從最便宜的存量格買起 → taking = 存量區最前（最便宜）的 n 格。
 * @param {string} resource
 * @returns {{price: number, slots: string[]}[]}
 */
function groupsOf(resource) {
  const steps = ladder(resource)
  const count = market.value?.[resource]?.count ?? 0
  const firstFilled = steps.length - count
  const taking = takingOf(resource)
  /** @type {{price: number, slots: string[]}[]} */
  const groups = []
  steps.forEach((price, index) => {
    const state =
      index < firstFilled ? 'empty' : index < firstFilled + taking ? 'taking' : 'filled'
    const last = groups[groups.length - 1]
    if (last && last.price === price) last.slots.push(state)
    else groups.push({ price, slots: [state] })
  })
  return groups
}

/** @param {string} resource */
const nextPrice = (resource) => cost(resource, market.value?.[resource]?.count ?? 0, 1)
/** @param {string} resource */
const takingCost = (resource) =>
  cost(resource, market.value?.[resource]?.count ?? 0, takingOf(resource))
</script>

<template>
  <div v-if="market" class="resource-market" :class="embedded ? 'embedded' : 'panel'">
    <h3>資源市場 <span class="hint">單價看存量：越買越貴、補貨變便宜</span></h3>
    <div v-for="(meta, resource) in RESOURCE_META" :key="resource" class="rm-row">
      <span class="rm-icon" :title="meta.label">{{ meta.icon }}</span>
      <div class="rm-ladder">
        <div v-for="group in groupsOf(resource)" :key="group.price" class="rm-group">
          <div class="rm-slots">
            <span
              v-for="(state, index) in group.slots"
              :key="index"
              class="rm-slot"
              :class="state"
            ></span>
          </div>
          <span class="rm-price">{{ group.price }}</span>
        </div>
      </div>
      <span v-if="takingOf(resource) > 0" class="rm-next rm-taking-label">
        −{{ takingOf(resource) }} → ${{ takingCost(resource) }}
      </span>
      <span v-else class="rm-next hint">
        <template v-if="nextPrice(resource) != null">×{{ market[resource].count }}・${{ nextPrice(resource) }}</template>
        <template v-else>售罄</template>
      </span>
    </div>
  </div>
</template>
