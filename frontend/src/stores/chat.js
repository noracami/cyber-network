import { defineStore } from 'pinia'
import { push } from '../channels/socket'
import { useRoomStore } from './room'

/**
 * @typedef {Object} ChatMessage
 * @property {number} id
 * @property {'chat' | 'sys'} kind
 * @property {string | null} from
 * @property {string | null} name
 * @property {string} text
 * @property {string} at - ISO 8601
 */

const LIMIT = 200

export const useChatStore = defineStore('chat', {
  state: () => ({
    /** @type {ChatMessage[]} */
    messages: [],
    /** @type {'all' | 'chat' | 'sys'} */
    tab: 'all',
  }),

  getters: {
    filtered(state) {
      if (state.tab === 'all') return state.messages
      return state.messages.filter((m) => m.kind === state.tab)
    },
  },

  actions: {
    /** join 快照的歷史訊息（時間序） */
    reset(messages) {
      this.messages = messages
    },
    /** @param {ChatMessage} message */
    add(message) {
      this.messages.push(message)
      if (this.messages.length > LIMIT) this.messages.splice(0, this.messages.length - LIMIT)
    },
    /** @param {string} text */
    async send(text) {
      const trimmed = text.trim()
      if (!trimmed) return
      const room = useRoomStore()
      if (room.demoMode) {
        this.add({
          id: Date.now(),
          kind: 'chat',
          from: room.selfId,
          name: room.nameOf(room.selfId || ''),
          text: trimmed,
          at: new Date().toISOString(),
        })
        return
      }
      await push('chat_send', { text: trimmed })
    },
  },
})
