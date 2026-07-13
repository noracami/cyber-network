import { createPinia } from 'pinia'
import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import { useRoomStore } from './stores/room'
import { useSettingsStore } from './stores/settings'
import './style.css'

const pinia = createPinia()

/** OAuth callback 用 URL hash 帶回登入 token（或錯誤標記）——
 *  必須在 router 接管 hash 前消費掉,否則 catch-all redirect 會把它洗掉。 */
function consumeAuthHash() {
  const hash = location.hash
  if (hash.startsWith('#discord_token=')) {
    useSettingsStore(pinia).setDiscordToken(
      decodeURIComponent(hash.slice('#discord_token='.length))
    )
    history.replaceState(null, '', location.pathname)
  } else if (hash.startsWith('#discord_error')) {
    useRoomStore(pinia).flashError('Discord 登入失敗，請再試一次')
    history.replaceState(null, '', location.pathname)
  }
}
consumeAuthHash()

createApp(App).use(pinia).use(router).mount('#app')
