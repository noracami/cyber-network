<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { eventText } from '../game/text'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'

const room = useRoomStore()
const staticStore = useStaticStore()

const listEl = ref(/** @type {HTMLElement | null} */ (null))

const lines = computed(() =>
  room.eventLog
    .map((event) => ({ seq: event.seq, text: eventText(event, room.nameOf, staticStore.cityName) }))
    .filter((line) => line.text !== null)
)

watch(
  () => lines.value.length,
  async () => {
    await nextTick()
    if (listEl.value) listEl.value.scrollTop = listEl.value.scrollHeight
  }
)
</script>

<template>
  <div class="game-log panel">
    <h3>事件紀錄</h3>
    <div ref="listEl" class="log-list">
      <div v-for="line in lines" :key="line.seq" class="log-line">{{ line.text }}</div>
    </div>
  </div>
</template>
