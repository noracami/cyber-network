import { defineStore } from 'pinia'

/** 純前端 UI 狀態（彈窗開闔）——不進 WebSocket、不持久化。 */
export const useUiStore = defineStore('ui', {
  state: () => ({
    /** @type {string | null} 規則彈窗目前分頁；null = 關閉 */
    rulesTab: null,
    /** @type {number | null} 收入表要高亮的供電數（從官僚階段開啟時帶入） */
    payoutHighlight: null,
    /** @type {number | null} 電廠詳情彈窗的卡號 */
    detailPlant: null,
    /** 帳密登入／註冊彈窗 */
    loginOpen: false,
  }),

  actions: {
    /**
     * @param {string} [tab]
     * @param {number | null} [payoutHighlight]
     */
    openRules(tab = 'flow', payoutHighlight = null) {
      this.rulesTab = tab
      this.payoutHighlight = payoutHighlight
    },
    closeRules() {
      this.rulesTab = null
      this.payoutHighlight = null
    },
    /** @param {number} number */
    showPlant(number) {
      this.detailPlant = number
    },
    closePlant() {
      this.detailPlant = null
    },
    openLogin() {
      this.loginOpen = true
    },
    closeLogin() {
      this.loginOpen = false
    },
  },
})
