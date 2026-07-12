import { defineStore } from 'pinia'

const TOKEN_KEY = 'gm_token'
const NAME_KEY = 'gm_name'
const DISCORD_KEY = 'gm_discord_token'
const MAP_LAYOUT_KEY = 'gm_map_layout'

/** 確保 localStorage 有一組隨機 token——它就是玩家身份（斷線重連的鑰匙）。 */
function ensureToken() {
  let token = localStorage.getItem(TOKEN_KEY)
  if (!token) {
    token = crypto.randomUUID()
    localStorage.setItem(TOKEN_KEY, token)
  }
  return token
}

export const useSettingsStore = defineStore('settings', {
  state: () => ({
    token: ensureToken(),
    name: localStorage.getItem(NAME_KEY) || '',
    /** Discord 登入 token（後端簽發，30 天有效） */
    discordToken: localStorage.getItem(DISCORD_KEY) || '',
    /** 地圖佈局：'geo' 地理位置｜'grid' 垂直水平線路 */
    mapLayout: localStorage.getItem(MAP_LAYOUT_KEY) === 'grid' ? 'grid' : 'geo',
  }),
  actions: {
    /** @param {string} name */
    setName(name) {
      this.name = name.trim().slice(0, 20)
      localStorage.setItem(NAME_KEY, this.name)
    },
    /** @param {string} token */
    setDiscordToken(token) {
      this.discordToken = token
      localStorage.setItem(DISCORD_KEY, token)
    },
    clearDiscordToken() {
      this.discordToken = ''
      localStorage.removeItem(DISCORD_KEY)
    },
    toggleMapLayout() {
      this.mapLayout = this.mapLayout === 'grid' ? 'geo' : 'grid'
      localStorage.setItem(MAP_LAYOUT_KEY, this.mapLayout)
    },
  },
})
