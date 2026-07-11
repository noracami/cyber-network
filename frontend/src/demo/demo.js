// 展示模式（網址加 ?demo）——不連 WebSocket，把假資料灌進 Pinia store，
// 讓所有元件走真實資料流渲染。純視覺驗收用：動作一律不送出（store 層攔截）。
import { ref } from 'vue'
import { useChatStore } from '../stores/chat'
import { useRoomStore } from '../stores/room'
import { useStaticStore } from '../stores/staticData'

const SELF = 'demo_self'
const P2 = 'demo_p2'
const P3 = 'demo_p3'

/** @type {{selfPlants: any[], p2Plants: any[], p3Plants: any[]} | null} */
let seeded = null

export const scenario = ref('auction')

export const SCENARIOS = [
  { key: 'auction', label: '競標｜提名' },
  { key: 'bidding', label: '競標｜出價' },
  { key: 'discard', label: '競標｜棄置' },
  { key: 'resources', label: '採購資源' },
  { key: 'building', label: '擴建網路' },
  { key: 'bureaucracy', label: '結算供電' },
  { key: 'game_over', label: '終局' },
]

export function isDemo() {
  return new URLSearchParams(location.search).has('demo')
}

export async function enterDemo() {
  const room = useRoomStore()
  const staticStore = useStaticStore()
  room.demoMode = true
  await staticStore.load()
  if (staticStore.failed) return
  seed()
  applyScenario('auction')
}

/** 從真實地圖與牌庫組出一局「第 5 回合、Step 2」的中盤局面 */
function seed() {
  const staticStore = useStaticStore()
  const room = useRoomStore()
  const chat = useChatStore()

  const map = staticStore.map
  const plants = staticStore.deck.plants

  // 每種類型撈一張湊多樣性：自己拿 自持/混合/水力，對手分掉其他
  const byType = (type) => plants.filter((p) => p.type === type)
  const pick = [
    byType('self')[0],
    byType('hybrid')[0],
    byType('hydro')[0],
    byType('thermal')[0],
    byType('thermal')[1],
    byType('waste')[0],
    byType('quantum')[0],
  ].filter(Boolean)
  const selfPlants = pick.slice(0, 3)
  const p2Plants = pick.slice(3, 5)
  const p3Plants = pick.slice(5, 7)
  seeded = { selfPlants, p2Plants, p3Plants }

  // 啟用全部叢集只留一個反灰，順便展示未啟用區域的視覺
  const regionIds = map.regions.map((r) => r.id)
  const active = regionIds.slice(0, regionIds.length - 1)

  // 佔據第一個叢集的城市；首城雙人進駐（Step 2 的第二格）
  const home = map.cities.filter((c) => c.region === regionIds[0]).map((c) => c.id)
  const selfCities = home.slice(0, 3)
  const p2Cities = [...home.slice(3, 5), home[0]]
  const p3Cities = home.slice(5, 7)

  /** @type {Record<string, string[]>} */
  const cityOwners = {}
  for (const city of selfCities) cityOwners[city] = [SELF]
  for (const city of home.slice(3, 5)) cityOwners[city] = [P2]
  for (const city of p3Cities) cityOwners[city] = [P3]
  cityOwners[home[0]] = [SELF, P2]

  // 卡牌市場 = 未被持有的最小 8 張
  const ownedNumbers = new Set(pick.map((p) => p.number))
  const marketNumbers = plants
    .map((p) => p.number)
    .filter((n) => !ownedNumbers.has(n))
    .sort((a, b) => a - b)
    .slice(0, 8)

  room.game = {
    round: 5,
    step: 2,
    phase: 'auction',
    final_round: false,
    turn_order: [SELF, P2, P3],
    deck_count: 23,
    market: { actual: marketNumbers.slice(0, 4), future: marketNumbers.slice(4, 8) },
    resource_market: {
      hydro: { count: 16 },
      thermal: { count: 11 },
      waste: { count: 4 },
      quantum: { count: 3 },
    },
    active_regions: active,
    city_owners: cityOwners,
    players: {
      [SELF]: {
        credits: 87,
        plants: selfPlants,
        resources: { hydro: 3, thermal: 2, waste: 1, quantum: 1 },
        cities: selfCities,
      },
      [P2]: {
        credits: 64,
        plants: p2Plants,
        resources: { hydro: 1, thermal: 2, waste: 0, quantum: 0 },
        cities: p2Cities,
      },
      [P3]: {
        credits: 102,
        plants: p3Plants,
        resources: { hydro: 0, thermal: 0, waste: 1, quantum: 1 },
        cities: p3Cities,
      },
    },
    phase_state: {},
  }

  room.selfId = SELF
  room.connected = true
  room.status = 'in_game'
  room.seats = [SELF, P2, P3]
  room.users = {
    [SELF]: { name: '阿電', role: 'user', ready: true, online: true, seated: true },
    [P2]: { name: '小網', role: 'user', ready: true, online: true, seated: true },
    [P3]: { name: '大算', role: 'user', ready: true, online: true, seated: true },
    demo_watcher: { name: '路過的訪客', role: 'guest', ready: false, online: true, seated: false },
  }

  room.eventLog = []
  room.eventSeq = 0
  room.applyEvents([
    { type: 'round_started', round: 5 },
    { type: 'turn_order_changed', turn_order: [SELF, P2, P3] },
    { type: 'phase_changed', phase: 'auction' },
    { type: 'plant_bought', player: P2, plant: p2Plants[0]?.number, price: 24 },
    { type: 'city_built', player: SELF, city: selfCities[2], cost: 18 },
    { type: 'powered', player: P3, powered: 2, income: 33 },
  ])

  const at = new Date().toISOString()
  chat.reset([
    { id: 1, kind: 'sys', from: null, name: null, text: '展示模式：以下皆為假資料', at },
    { id: 2, kind: 'chat', from: P2, name: '小網', text: '這波算力有點貴啊', at },
    { id: 3, kind: 'chat', from: SELF, name: '阿電', text: '先搶節點再說', at },
  ])
}

/** @param {string} key */
export function applyScenario(key) {
  const room = useRoomStore()
  if (!room.game || !seeded) return
  scenario.value = key

  const game = { ...room.game, final_round: false }
  room.status = 'in_game'
  room.result = null

  switch (key) {
    case 'auction':
      game.phase = 'auction'
      game.phase_state = { queue: [SELF, P2, P3], bought: {}, bidding: null, pending_discard: null }
      break
    case 'bidding':
      game.phase = 'auction'
      game.phase_state = {
        queue: [P2, SELF, P3],
        bought: {},
        bidding: {
          plant: game.market.actual[1],
          price: game.market.actual[1] + 3,
          leader: P2,
          turn: SELF,
          active: [SELF, P2],
        },
        pending_discard: null,
      }
      break
    case 'discard':
      game.phase = 'auction'
      game.phase_state = {
        queue: [P2, P3],
        bought: { [SELF]: seeded.selfPlants[2]?.number },
        bidding: null,
        pending_discard: SELF,
      }
      break
    case 'resources':
      game.phase = 'resources'
      game.phase_state = { queue: [SELF, P2] }
      break
    case 'building':
      game.phase = 'building'
      game.phase_state = { queue: [SELF, P3] }
      break
    case 'bureaucracy':
      game.phase = 'bureaucracy'
      game.phase_state = { submitted: [P2] }
      break
    case 'game_over':
      room.status = 'game_over'
      room.result = {
        winner: SELF,
        ranking: [
          { player: SELF, powered: 11, credits: 42, cities: 12 },
          { player: P2, powered: 9, credits: 78, cities: 10 },
          { player: P3, powered: 9, credits: 31, cities: 11 },
        ],
      }
      break
  }

  room.game = game
}
