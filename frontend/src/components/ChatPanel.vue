<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { useChatStore } from '../stores/chat'
import { useRoomStore } from '../stores/room'

const chat = useChatStore()
const room = useRoomStore()

const draft = ref('')
const listEl = ref(/** @type {HTMLElement | null} */ (null))

// 手機（R3）：聊天預設收合成標題列，收合期間累計未讀
const isMobile = window.matchMedia('(max-width: 700px)').matches
const open = ref(!isMobile)
const seenCount = ref(0)
const unread = computed(() => Math.max(0, chat.messages.length - seenCount.value))

function toggle() {
  open.value = !open.value
  if (open.value) seenCount.value = chat.messages.length
}

const TABS = [
  { key: 'all', label: 'All' },
  { key: 'chat', label: 'Chat' },
  { key: 'sys', label: 'Sysmsg' },
]

watch(
  () => chat.messages.length,
  async (count) => {
    if (open.value) seenCount.value = count
    await nextTick()
    if (listEl.value) listEl.value.scrollTop = listEl.value.scrollHeight
  }
)

/** @param {KeyboardEvent} event */
function onEnter(event) {
  // 中文輸入法選字中的 Enter 不送出
  if (event.isComposing) return
  submit()
}

async function submit() {
  const text = draft.value
  if (!text.trim()) return
  draft.value = ''
  try {
    await chat.send(text)
  } catch {
    room.flashError('訊息傳送失敗')
    draft.value = text
  }
}

/** @param {string} at ISO 時間 → 使用者本地時區的 HH:MM */
function timeOf(at) {
  const d = new Date(at)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
</script>

<template>
  <aside class="chat" :class="{ collapsed: isMobile && !open }">
    <button v-if="isMobile" class="collapse-head" @click="toggle">
      <span>💬 聊天<span v-if="unread && !open" class="chat-unread">{{ unread }}</span></span>
      <span class="collapse-arrow">{{ open ? '▾' : '▸' }}</span>
    </button>

    <nav v-show="!isMobile || open" class="chat-tabs">
      <button
        v-for="tab in TABS"
        :key="tab.key"
        class="tab"
        :class="{ active: chat.tab === tab.key }"
        @click="chat.tab = /** @type {'all' | 'chat' | 'sys'} */ (tab.key)"
      >
        {{ tab.label }}
      </button>
    </nav>

    <div v-show="!isMobile || open" ref="listEl" class="chat-list">
      <!-- kind- 前綴避免撞到 .chat／.sys 這類全域 class（曾被 .chat 的 300px 打中） -->
      <div v-for="message in chat.filtered" :key="message.id" class="chat-msg" :class="'kind-' + message.kind">
        <template v-if="message.kind === 'chat'">
          <div class="chat-msg-head">
            <span class="chat-time">{{ timeOf(message.at) }}</span>
            <span class="chat-name" :class="{ self: message.from === room.selfId }">{{ message.name }}</span>
          </div>
          <div class="chat-text">{{ message.text }}</div>
        </template>
        <template v-else>
          <span class="chat-time">{{ timeOf(message.at) }}</span>
          <span class="chat-sys">⚙ {{ message.text }}</span>
        </template>
      </div>
    </div>

    <div v-show="!isMobile || open" class="chat-input">
      <input
        v-model="draft"
        type="text"
        maxlength="300"
        placeholder="輸入訊息…"
        @keydown.enter="onEnter"
      />
      <button class="btn primary" @click="submit">送出</button>
    </div>
  </aside>
</template>
