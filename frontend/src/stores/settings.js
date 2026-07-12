import { defineStore } from 'pinia'

const TOKEN_KEY = 'gm_token'
const NAME_KEY = 'gm_name'
const DISCORD_KEY = 'gm_discord_token'
const PASSWORD_KEY = 'gm_password_token'
const MAP_LAYOUT_KEY = 'gm_map_layout'
const MAP_NAV_KEY = 'gm_map_nav'

/** 確保 localStorage 有一組隨機 token——它就是玩家身份（斷線重連的鑰匙）。 */
function ensureToken() {
  let token = localStorage.getItem(TOKEN_KEY)
  if (!token) {
    token = crypto.randomUUID()
    localStorage.setItem(TOKEN_KEY, token)
  }
  return token
}

/** 地圖縮放預設：桌機關（鎖定全覽）、觸控裝置開（R3——手機全覽太小，捏合縮放是剛需） */
function defaultMapNav() {
  const saved = localStorage.getItem(MAP_NAV_KEY)
  if (saved != null) return saved === 'on'
  return window.matchMedia('(pointer: coarse)').matches
}

export const useSettingsStore = defineStore('settings', {
  state: () => ({
    token: ensureToken(),
    name: localStorage.getItem(NAME_KEY) || '',
    /** Discord 登入 token（後端簽發，30 天有效） */
    discordToken: localStorage.getItem(DISCORD_KEY) || '',
    /** 帳密登入 token（M10；同為後端簽發、30 天有效） */
    passwordToken: localStorage.getItem(PASSWORD_KEY) || '',
    /** 地圖佈局：'grid' 垂直水平線路（預設）｜'geo' 地理位置 */
    mapLayout: localStorage.getItem(MAP_LAYOUT_KEY) === 'geo' ? 'geo' : 'grid',
    /** 地圖縮放平移：使用者切過就記住，否則依裝置預設 */
    mapNav: defaultMapNav(),
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
    /** @param {string} token */
    setPasswordToken(token) {
      this.passwordToken = token
      localStorage.setItem(PASSWORD_KEY, token)
    },
    clearPasswordToken() {
      this.passwordToken = ''
      localStorage.removeItem(PASSWORD_KEY)
    },
    toggleMapLayout() {
      this.mapLayout = this.mapLayout === 'grid' ? 'geo' : 'grid'
      localStorage.setItem(MAP_LAYOUT_KEY, this.mapLayout)
    },
    toggleMapNav() {
      this.mapNav = !this.mapNav
      localStorage.setItem(MAP_NAV_KEY, this.mapNav ? 'on' : 'off')
    },
  },
})
