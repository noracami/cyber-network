import { defineStore } from 'pinia'
import { push } from '../channels/socket'

/**
 * @typedef {Object} RoomUser
 * @property {string} name
 * @property {string} role   - "guest" | "admin"
 * @property {boolean} ready
 * @property {boolean} online
 * @property {boolean} seated
 */

/** 後端錯誤原因 → 顯示文案 */
const ERROR_TEXT = {
  not_your_turn: '還沒輪到你',
  not_in_lobby: '目前不在大廳',
  not_seated: '你還沒入座',
  already_seated: '你已經入座了',
  room_full: '座位已滿',
  not_enough_players: '至少需要 2 位玩家',
  not_all_ready: '還有人沒準備好',
  not_game_over: '遊戲還沒結束',
  not_in_game: '遊戲尚未開始',
  unknown_player: '你不是本局玩家',
  insufficient_credits: '能量點數不足',
  insufficient_market: '市場存量不足',
  insufficient_resources: '資源不足',
  storage_exceeded: '超過設施儲存容量',
  bid_too_low: '出價太低',
  plant_not_available: '這張卡目前不可競標',
  must_buy_first_round: '第一回合必須買一座設施',
  city_full: '這個節點已滿',
  city_not_active: '這個節點不在本局範圍',
  already_built_here: '你已佔據這個節點',
  unreachable: '無法連通到這個節點',
  forbidden: '權限不足',
  timeout: '伺服器回應逾時',
}

export const useRoomStore = defineStore('room', {
  state: () => ({
    connected: false,
    /** @type {string | null} */
    selfId: null,
    /** @type {'lobby' | 'in_game' | 'game_over'} */
    status: 'lobby',
    /** @type {string[]} */
    seats: [],
    /** @type {Record<string, RoomUser>} */
    users: {},
    /** @type {object | null} 引擎視圖（View.render 輸出） */
    game: null,
    /** @type {object | null} 終局排名 */
    result: null,
    /** @type {object[]} 最近一批 game_events */
    lastEvents: [],
    /** @type {object[]} 事件日誌（GameLog 顯示，上限 120 筆） */
    eventLog: [],
    eventSeq: 0,
    /** @type {string | null} */
    lastError: null,
    /** @type {ReturnType<typeof setTimeout> | null} */
    errorTimer: null,
  }),

  getters: {
    self(state) {
      return (state.selfId && state.users[state.selfId]) || null
    },
    seated(state) {
      return state.selfId != null && state.seats.includes(state.selfId)
    },
    isAdmin(state) {
      return state.selfId != null && state.users[state.selfId]?.role === 'admin'
    },
    allReady(state) {
      return state.seats.length >= 2 && state.seats.every((id) => state.users[id]?.ready)
    },
    spectators(state) {
      return Object.entries(state.users)
        .filter(([id]) => !state.seats.includes(id))
        .map(([id, user]) => ({ id, ...user }))
    },
    /** @returns {(id: string) => string} */
    nameOf(state) {
      return (id) => state.users[id]?.name || id
    },
  },

  actions: {
    /** room_sync 廣播（全量狀態） */
    applySync(payload) {
      this.status = payload.status
      this.seats = payload.seats
      this.users = payload.users
      this.game = payload.game
      this.result = payload.result
    },
    /** join 回覆的快照（比 sync 多 self） */
    applySnapshot(snapshot) {
      this.selfId = snapshot.self
      this.applySync(snapshot)
    },
    applyEvents(events) {
      this.lastEvents = events
      for (const event of events) {
        this.eventLog.push({ seq: ++this.eventSeq, ...event })
      }
      if (this.eventLog.length > 120) {
        this.eventLog.splice(0, this.eventLog.length - 120)
      }
    },

    // --- 對後端的操作 ---
    seatTake() {
      return this.op('seat_take')
    },
    seatLeave() {
      return this.op('seat_leave')
    },
    ready() {
      return this.op('ready')
    },
    unready() {
      return this.op('unready')
    },
    gameStart() {
      return this.op('game_start')
    },
    backToLobby() {
      return this.op('back_to_lobby')
    },
    adminAbort() {
      return this.op('admin_abort')
    },
    /**
     * @param {string} type 引擎動作名（如 auction_choose）
     * @param {object} payload
     */
    gameAction(type, payload = {}) {
      return this.op('action', { type, payload })
    },

    async op(event, payload = {}) {
      try {
        await push(event, payload)
      } catch (err) {
        this.flashError(err instanceof Error ? err.message : String(err))
      }
    },

    flashError(reason) {
      this.lastError = ERROR_TEXT[reason] || reason
      if (this.errorTimer) clearTimeout(this.errorTimer)
      this.errorTimer = setTimeout(() => {
        this.lastError = null
      }, 4000)
    },
  },
})
