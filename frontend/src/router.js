import { createRouter, createWebHashHistory } from 'vue-router'
import GameShell from './components/GameShell.vue'

/**
 * Hash mode router(Phoenix 只在 `/` 服務 SPA,hash 深連結零伺服器配置)。
 *
 * `/r/:roomId` 是 `/` 的 alias——同一個 route record,主頁↔房間切換不會
 * 重掛 GameShell;實際的切房(leave/join channel)仍由 socket.js 的
 * hashchange 監聽處理,router 只負責頁面層。
 */
export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', component: GameShell, alias: '/r/:roomId' },
    { path: '/gallery', component: () => import('./components/GalleryView.vue') },
    { path: '/admin/cards', component: () => import('./components/AdminCardsView.vue') },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})
