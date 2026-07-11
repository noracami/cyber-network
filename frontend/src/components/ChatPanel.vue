<script setup>
import { nextTick, ref, watch } from 'vue'
import { useChatStore } from '../stores/chat'
import { useRoomStore } from '../stores/room'

const chat = useChatStore()
const room = useRoomStore()

const draft = ref('')
const listEl = ref(/** @type {HTMLElement | null} */ (null))

const TABS = [
  { key: 'all', label: 'All' },
  { key: 'chat', label: 'Chat' },
  { key: 'sys', label: 'Sysmsg' },
]

watch(
  () => chat.messages.length,
  async () => {
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

/** @param {string} at */
function timeOf(at) {
  return at.slice(11, 16)
}
</script>

<template>
  <aside class="chat">
    <nav class="chat-tabs">
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

    <div ref="listEl" class="chat-list">
      <div v-for="message in chat.filtered" :key="message.id" class="chat-msg" :class="message.kind">
        <template v-if="message.kind === 'chat'">
          <span class="chat-time">{{ timeOf(message.at) }}</span>
          <span class="chat-name" :class="{ self: message.from === room.selfId }">{{ message.name }}</span>
          <span class="chat-text">{{ message.text }}</span>
        </template>
        <template v-else>
          <span class="chat-time">{{ timeOf(message.at) }}</span>
          <span class="chat-sys">⚙ {{ message.text }}</span>
        </template>
      </div>
    </div>

    <div class="chat-input">
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
