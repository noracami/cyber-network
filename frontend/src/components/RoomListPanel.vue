<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

const rooms = ref(/** @type {{id: string, status: string, seated: number, online: number}[]} */ ([]))
const loading = ref(false)

const STATUS_TEXT = { lobby: '等待中', in_game: '對戰中', game_over: '結算中' }

// 房號字元表：小寫英數排除易混淆的 0/o/1/l，恰 32 字元（隨機位元組取模零偏差）
const CODE_ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'

const canOpen = computed(() => room.self && room.self.role !== 'guest')
const others = computed(() => rooms.value.filter((r) => r.id !== room.roomId))

async function refresh() {
  loading.value = true
  try {
    const resp = await fetch('/api/rooms')
    if (resp.ok) rooms.value = (await resp.json()).rooms
  } catch {
    // 輪詢失敗靜默：下一輪再試
  } finally {
    loading.value = false
  }
}

function newRoomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(5))
  return [...bytes].map((b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('')
}

function openRoom() {
  location.hash = `#/r/${newRoomCode()}`
}

/** @param {string} id */
function joinRoom(id) {
  location.hash = `#/r/${id}`
}

/** @type {ReturnType<typeof setInterval> | null} */
let timer = null

onMounted(() => {
  refresh()
  timer = setInterval(refresh, 30000)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <section class="panel room-list">
    <div class="room-list-head">
      <h3>房間</h3>
      <button class="btn ghost" :disabled="loading" title="重新整理" @click="refresh()">🔄</button>
      <button v-if="canOpen" class="btn primary" @click="openRoom()">＋開新房間</button>
    </div>

    <p v-if="!canOpen" class="hint">登入後可開新房間，和朋友分享連結對戰。</p>

    <ul v-if="others.length" class="room-list-items">
      <li v-for="entry in others" :key="entry.id">
        <button class="room-item" @click="joinRoom(entry.id)">
          <span class="room-code">#{{ entry.id }}</span>
          <span class="room-status" :class="`is-${entry.status}`">
            {{ STATUS_TEXT[entry.status] || entry.status }}
          </span>
          <span class="room-count">{{ entry.seated }}/6 座・{{ entry.online }} 在線</span>
        </button>
      </li>
    </ul>
    <p v-else class="hint">目前沒有其他房間。</p>
  </section>
</template>
