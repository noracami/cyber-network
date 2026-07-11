import { defineStore } from 'pinia'

/** 靜態遊戲數據（地圖／卡牌／規則）——開站抓一次，全程不變。 */
export const useStaticStore = defineStore('staticData', {
  state: () => ({
    /** @type {object | null} */
    map: null,
    /** @type {object | null} */
    deck: null,
    /** @type {object | null} */
    rules: null,
    loaded: false,
    failed: false,
  }),

  getters: {
    /** @returns {Map<number, object>} 卡號 → 卡牌數據 */
    plantsByNumber(state) {
      return new Map((state.deck?.plants || []).map((p) => [p.number, p]))
    },
    /** @returns {Map<string, object>} 城市 id → 城市數據 */
    citiesById(state) {
      return new Map((state.map?.cities || []).map((c) => [c.id, c]))
    },
    /** @returns {(id: string) => string} */
    cityName() {
      return (id) => this.citiesById.get(id)?.name || id
    },
    /** @returns {number[]} 供電收入表 */
    payout(state) {
      return state.rules?.payout || []
    },
  },

  actions: {
    async load() {
      if (this.loaded) return
      try {
        const resp = await fetch('/api/static')
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
        const body = await resp.json()
        this.map = body.map
        this.deck = body.deck
        this.rules = body.rules
        this.loaded = true
      } catch {
        this.failed = true
      }
    },
  },
})
