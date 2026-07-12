import { Socket } from 'phoenix'
import { useChatStore } from '../stores/chat'
import { useRoomStore } from '../stores/room'
import { useSettingsStore } from '../stores/settings'

/** @type {Socket | null} */
let socket = null
/** @type {import('phoenix').Channel | null} */
let channel = null
/** @type {(() => void) | null} */
let hashHandler = null

/** 房號 hash 路由（PRD-v1.5 R2）：#/r/<id> ↔ room:<id>，無 hash = main */
const ROOM_HASH = /^#\/r\/([a-z0-9]{4,6})$/

export function roomIdFromHash() {
  const match = location.hash.match(ROOM_HASH)
  return match ? match[1] : 'main'
}

function wsUrl() {
  if (import.meta.env.VITE_WS_URL) return import.meta.env.VITE_WS_URL
  if (import.meta.env.DEV) return 'ws://localhost:4000/socket'
  // 生產環境：同網域，由 Caddy 反向代理 /socket
  return location.origin.replace(/^http/, 'ws') + '/socket'
}

/** 建立 WebSocket 連線並加入 hash 指定的房間。Phoenix Socket 會自動斷線重連＋重新 join。 */
export function connect() {
  const settings = useSettingsStore()
  const room = useRoomStore()

  // 展示模式不連線——真實 room_sync 會蓋掉假資料
  if (room.demoMode) return

  socket = new Socket(wsUrl(), {
    params: {
      token: settings.token,
      name: settings.name || '訪客',
      // 有登入 token 就帶上；後端優先驗 Discord、再驗帳密，都失敗退回訪客
      ...(settings.discordToken ? { discord_token: settings.discordToken } : {}),
      ...(settings.passwordToken ? { password_token: settings.passwordToken } : {}),
    },
  })
  socket.onOpen(() => {
    room.connected = true
  })
  socket.onClose(() => {
    room.connected = false
  })
  socket.onError(() => {
    room.connected = false
  })
  socket.connect()

  joinRoom(roomIdFromHash())

  if (!hashHandler) {
    hashHandler = () => {
      const id = roomIdFromHash()
      if (id !== useRoomStore().roomId) joinRoom(id)
    }
    window.addEventListener('hashchange', hashHandler)
  }
}

/** 切房＝leave 舊 channel＋join 新 channel（同一條 socket），房間狀態歸零等新快照。 */
function joinRoom(roomId) {
  const room = useRoomStore()
  const chat = useChatStore()

  if (channel) channel.leave()
  room.enterRoom(roomId)

  channel = socket.channel(`room:${roomId}`, {})
  channel.on('room_sync', (payload) => room.applySync(payload))
  channel.on('game_events', (payload) => room.applyEvents(payload.events))
  channel.on('chat_new', (message) => chat.add(message))

  channel
    .join()
    .receive('ok', (snapshot) => {
      room.applySnapshot(snapshot)
      chat.reset(snapshot.chat)
    })
    .receive('error', (resp) => {
      room.flashError(resp?.reason === 'invalid_room' ? 'invalid_room' : '加入房間失敗')
      // 房號不合法就退回 main
      if (resp?.reason === 'invalid_room' && roomId !== 'main') {
        location.hash = ''
      }
    })
}

/** 改名等需要重建連線參數的場合使用。 */
export function reconnect() {
  if (channel) channel.leave()
  if (socket) socket.disconnect()
  connect()
}

/**
 * 送事件到房間 channel。
 * @param {string} event
 * @param {object} payload
 * @returns {Promise<unknown>} ok 回應內容；error/timeout 時 reject(Error(reason))
 */
export function push(event, payload = {}) {
  return new Promise((resolve, reject) => {
    if (!channel) return reject(new Error('尚未連線'))
    channel
      .push(event, payload)
      .receive('ok', resolve)
      .receive('error', (resp) => reject(new Error(resp?.reason || 'error')))
      .receive('timeout', () => reject(new Error('timeout')))
  })
}
