import { Socket } from 'phoenix'
import { useChatStore } from '../stores/chat'
import { useRoomStore } from '../stores/room'
import { useSettingsStore } from '../stores/settings'

/** @type {Socket | null} */
let socket = null
/** @type {import('phoenix').Channel | null} */
let channel = null

function wsUrl() {
  if (import.meta.env.VITE_WS_URL) return import.meta.env.VITE_WS_URL
  if (import.meta.env.DEV) return 'ws://localhost:4000/socket'
  // 生產環境：同網域，由 Caddy 反向代理 /socket
  return location.origin.replace(/^http/, 'ws') + '/socket'
}

/** 建立 WebSocket 連線並加入 room:main。Phoenix Socket 會自動斷線重連＋重新 join。 */
export function connect() {
  const settings = useSettingsStore()
  const room = useRoomStore()
  const chat = useChatStore()

  // 展示模式不連線——真實 room_sync 會蓋掉假資料
  if (room.demoMode) return

  socket = new Socket(wsUrl(), {
    params: {
      token: settings.token,
      name: settings.name || '訪客',
      // 有 Discord 登入 token 就帶上；後端驗簽成功即用 Discord 身份，失敗退回訪客
      ...(settings.discordToken ? { discord_token: settings.discordToken } : {}),
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

  channel = socket.channel('room:main', {})
  channel.on('room_sync', (payload) => room.applySync(payload))
  channel.on('game_events', (payload) => room.applyEvents(payload.events))
  channel.on('chat_new', (message) => chat.add(message))

  channel
    .join()
    .receive('ok', (snapshot) => {
      room.applySnapshot(snapshot)
      chat.reset(snapshot.chat)
    })
    .receive('error', () => room.flashError('加入房間失敗'))
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
