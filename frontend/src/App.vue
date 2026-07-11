<script setup>
import { onMounted } from 'vue'
import { connect, reconnect } from './channels/socket'
import ChatPanel from './components/ChatPanel.vue'
import GameOverView from './components/GameOverView.vue'
import GameView from './components/GameView.vue'
import LobbyView from './components/LobbyView.vue'
import { useRoomStore } from './stores/room'
import { useSettingsStore } from './stores/settings'

const room = useRoomStore()
const settings = useSettingsStore()

onMounted(() => connect())

function changeName() {
  const name = window.prompt('輸入暱稱（最多 20 字）', settings.name)
  if (name !== null && name.trim() !== '') {
    settings.setName(name)
    reconnect()
  }
}
</script>

<template>
  <div class="app">
    <header class="topbar">
      <h1>⚡ Grid Master <span class="sub">CYBER NETWORK</span></h1>
      <div class="user-box">
        <span class="conn-dot" :class="room.connected ? 'on' : 'off'" :title="room.connected ? '已連線' : '連線中斷'"></span>
        <button class="btn ghost" @click="changeName">
          {{ room.self?.name || settings.name || '設定暱稱' }}
        </button>
        <button
          v-if="room.isAdmin && room.status !== 'lobby'"
          class="btn danger"
          @click="room.adminAbort()"
        >
          掀桌
        </button>
      </div>
    </header>

    <main class="layout">
      <section class="stage">
        <LobbyView v-if="room.status === 'lobby'" />
        <GameView v-else-if="room.status === 'in_game'" />
        <GameOverView v-else />
        <transition name="fade">
          <p v-if="room.lastError" class="error-toast">{{ room.lastError }}</p>
        </transition>
      </section>
      <ChatPanel />
    </main>

    <footer class="disclaimer">
      非商業粉絲致敬作品，遊戲機制致敬《Power Grid》（Friedemann Friese／2F-Spiele／Rio Grande
      Games）。本站不使用原作素材、不涉及任何商業行為，與原權利人無任何隸屬或授權關係。
    </footer>
  </div>
</template>
