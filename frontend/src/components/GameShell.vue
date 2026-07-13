<script setup>
import { onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { connect, reconnect, switchRoom } from '../channels/socket'
import { enterDemo, isDemo } from '../demo/demo'
import { useRoomStore } from '../stores/room'
import { useSettingsStore } from '../stores/settings'
import { useStaticStore } from '../stores/staticData'
import { useUiStore } from '../stores/ui'
import ChatPanel from './ChatPanel.vue'
import DemoToolbar from './DemoToolbar.vue'
import GameOverView from './GameOverView.vue'
import GameView from './GameView.vue'
import LobbyView from './LobbyView.vue'
import LoginModal from './LoginModal.vue'
import PlantDetailModal from './PlantDetailModal.vue'
import PlayerStrip from './PlayerStrip.vue'
import RoomListPanel from './RoomListPanel.vue'
import RulesModal from './RulesModal.vue'

const room = useRoomStore()
const settings = useSettingsStore()
const staticStore = useStaticStore()
const ui = useUiStore()
const router = useRouter()
const route = useRoute()

const demo = isDemo()

/** 路由參數 → 房號(`/` 與 `/r/:roomId` 共用本元件,無參數即 main) */
function routeRoomId() {
  return typeof route.params.roomId === 'string' ? route.params.roomId : 'main'
}

onMounted(() => {
  if (demo) {
    enterDemo()
    return
  }
  staticStore.load()
  connect(routeRoomId())
})

// 切房:router.push 走 pushState 不發 hashchange,統一由路由參數驅動
watch(
  () => route.params.roomId,
  () => switchRoom(routeRoomId())
)

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

const linkCopied = ref(false)

async function copyRoomLink() {
  const url = `${location.origin}${location.pathname}#/r/${room.roomId}`
  try {
    await navigator.clipboard.writeText(url)
    linkCopied.value = true
    setTimeout(() => {
      linkCopied.value = false
    }, 1500)
  } catch {
    window.prompt('複製這條房間連結', url)
  }
}

function backToMain() {
  router.push('/')
}
</script>

<template>
  <!-- 連線 splash：拿到第一份房間快照前的過場（demo 模式直接灌資料，不會經過） -->
  <transition name="fade">
    <div v-if="!demo && !room.selfId" class="splash">
      <svg class="splash-logo" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2.2 L20.5 7.1 V16.9 L12 21.8 L3.5 16.9 V7.1 Z" stroke="#37e6d4" stroke-width="1.6" stroke-linejoin="round" />
        <path d="M13.2 6.5 L8.6 13 H11.4 L10.4 17.5 L15.6 10.6 H12.6 L13.2 6.5 Z" fill="#37e6d4" />
        <line x1="12" y1="0" x2="12" y2="2.2" stroke="#37e6d4" stroke-width="1.4" />
        <line x1="12" y1="21.8" x2="12" y2="24" stroke="#37e6d4" stroke-width="1.4" />
      </svg>
      <div class="splash-title">GRID MASTER</div>
      <div class="splash-sub">CYBER NETWORK</div>
      <div class="splash-status">{{ room.connected ? '進入房間…' : '連線中…' }}</div>
    </div>
  </transition>

  <header class="topbar">
    <h1>
      <svg class="logo" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path d="M12 2.2 L20.5 7.1 V16.9 L12 21.8 L3.5 16.9 V7.1 Z" stroke="#37e6d4" stroke-width="1.6" stroke-linejoin="round" />
        <path d="M13.2 6.5 L8.6 13 H11.4 L10.4 17.5 L15.6 10.6 H12.6 L13.2 6.5 Z" fill="#37e6d4" />
        <line x1="12" y1="0" x2="12" y2="2.2" stroke="#37e6d4" stroke-width="1.4" />
        <line x1="12" y1="21.8" x2="12" y2="24" stroke="#37e6d4" stroke-width="1.4" />
      </svg>
      Grid Master <span class="sub">CYBER NETWORK</span>
    </h1>
    <div v-if="room.roomId !== 'main'" class="room-chip">
      <span class="room-code">#{{ room.roomId }}</span>
      <button class="btn ghost" @click="copyRoomLink()">
        {{ linkCopied ? '✔ 已複製' : '📋 複製連結' }}
      </button>
      <button class="btn ghost" @click="backToMain()">回大廳</button>
    </div>
    <div class="user-box">
      <router-link class="btn ghost" to="/gallery">🃏 圖鑑</router-link>
      <router-link v-if="room.isAdmin" class="btn ghost" to="/admin/cards">
        🎨 卡面工作台
      </router-link>
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
        v-if="(room.isAdmin || room.seated) && room.status !== 'lobby'"
        class="btn danger"
        @click="room.adminAbort()"
      >
        {{ room.isAdmin ? '掀桌' : '結束遊戲' }}
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
      <RoomListPanel v-if="!demo && room.roomId === 'main' && room.status === 'lobby'" />
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
</template>
