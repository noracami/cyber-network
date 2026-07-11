import { defineStore } from 'pinia'

const TOKEN_KEY = 'gm_token'
const NAME_KEY = 'gm_name'

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
  }),
  actions: {
    /** @param {string} name */
    setName(name) {
      this.name = name.trim().slice(0, 20)
      localStorage.setItem(NAME_KEY, this.name)
    },
  },
})
