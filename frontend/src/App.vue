<script setup>
import { onMounted } from 'vue'
import { connect, reconnect } from './channels/socket'
import ChatPanel from './components/ChatPanel.vue'
import DemoToolbar from './components/DemoToolbar.vue'
import GameOverView from './components/GameOverView.vue'
import GameView from './components/GameView.vue'
import LobbyView from './components/LobbyView.vue'
import LoginModal from './components/LoginModal.vue'
import PlantDetailModal from './components/PlantDetailModal.vue'
import PlayerStrip from './components/PlayerStrip.vue'
import RulesModal from './components/RulesModal.vue'
import { enterDemo, isDemo } from './demo/demo'
import { useRoomStore } from './stores/room'
import { useSettingsStore } from './stores/settings'
import { useStaticStore } from './stores/staticData'
import { useUiStore } from './stores/ui'

const room = useRoomStore()
const settings = useSettingsStore()
const staticStore = useStaticStore()
const ui = useUiStore()

/** OAuth callback 用 URL hash 帶回登入 token（或錯誤標記） */
function consumeAuthHash() {
  const hash = location.hash
  if (hash.startsWith('#discord_token=')) {
    settings.setDiscordToken(decodeURIComponent(hash.slice('#discord_token='.length)))
    history.replaceState(null, '', location.pathname)
  } else if (hash.startsWith('#discord_error')) {
    room.flashError('Discord 登入失敗，請再試一次')
    history.replaceState(null, '', location.pathname)
  }
}

const demo = isDemo()

onMounted(() => {
  if (demo) {
    enterDemo()
    return
  }
  consumeAuthHash()
  staticStore.load()
  connect()
})

function changeName() {
  const name = window.prompt('輸入暱稱（最多 20 字）', settings.name)
  if (name !== null && name.trim() !== '') {
    settings.setName(name)
    reconnect()
  }
}

function logoutDiscord() {
  settings.clearDiscordToken()
  reconnect()
}

function logoutPassword() {
  settings.clearPasswordToken()
  reconnect()
}
</script>

<template>
  <div class="app">
    <header class="topbar">
      <h1>⚡ Grid Master <span class="sub">CYBER NETWORK</span></h1>
      <div class="user-box">
        <button class="btn ghost" @click="ui.openRules()">📖 規則</button>
        <span class="conn-dot" :class="room.connected ? 'on' : 'off'" :title="room.connected ? '已連線' : '連線中斷'"></span>

        <template v-if="settings.discordToken">
          <img v-if="room.self?.avatar" :src="room.self.avatar" class="avatar" alt="" />
          <span class="self-name">{{ room.self?.name }}</span>
          <button class="btn ghost" @click="logoutDiscord">登出</button>
        </template>
        <template v-else-if="settings.passwordToken">
          <span class="self-name">{{ room.self?.name }}</span>
          <button class="btn ghost" @click="logoutPassword">登出</button>
        </template>
        <template v-else>
          <button class="btn ghost" @click="changeName">
            {{ room.self?.name || settings.name || '設定暱稱' }}
          </button>
          <button class="btn ghost" @click="ui.openLogin()">登入 / 註冊</button>
          <a class="btn primary" href="/auth/discord">Discord 登入</a>
        </template>

        <button
          v-if="room.isAdmin && room.status !== 'lobby'"
          class="btn danger"
          @click="room.adminAbort()"
        >
          掀桌
        </button>
      </div>
    </header>

    <DemoToolbar v-if="demo" />

    <main class="layout">
      <section class="stage">
        <LobbyView v-if="room.status === 'lobby'" />
        <GameView v-else-if="room.status === 'in_game'" />
        <GameOverView v-else />
        <transition name="fade">
          <p v-if="room.lastError" class="error-toast">{{ room.lastError }}</p>
        </transition>
      </section>
      <aside class="right-col">
        <PlayerStrip v-if="room.status === 'in_game'" />
        <ChatPanel />
      </aside>
    </main>

    <RulesModal />
    <PlantDetailModal />
    <LoginModal />

    <footer class="disclaimer">
      非商業粉絲致敬作品，遊戲機制致敬《Power Grid》（Friedemann Friese／2F-Spiele／Rio Grande
      Games）。本站不使用原作素材、不涉及任何商業行為，與原權利人無任何隸屬或授權關係。
    </footer>
  </div>
</template>
