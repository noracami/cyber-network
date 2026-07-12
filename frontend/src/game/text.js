// 顯示文案：資源／階段／事件的中文對照。

// icon（emoji）僅供純文字流使用（事件日誌、聊天、tooltip）；
// 面板 UI 一律改用 GameIcon.vue（v1.3 A1），color 為各類型專色。
export const RESOURCE_META = {
  hydro: { icon: '💧', label: '水力', color: '#4da6ff' },
  thermal: { icon: '🔥', label: '火力', color: '#fb923c' },
  waste: { icon: '♻️', label: '廢料', color: '#4ade80' },
  quantum: { icon: '🧠', label: '算力', color: '#e879f9' },
}

export const TYPE_META = {
  hydro: { icon: '💧', label: '水力', color: '#4da6ff' },
  thermal: { icon: '🔥', label: '火力', color: '#fb923c' },
  waste: { icon: '♻️', label: '廢料', color: '#4ade80' },
  quantum: { icon: '🧠', label: '算力', color: '#e879f9' },
  hybrid: { icon: '💧🔥', label: '混合', color: '#4da6ff' },
  self: { icon: '🍃', label: '自持', color: '#a3e635' },
  fusion: { icon: '🌀', label: '奇點', color: '#9d6bff' },
}

export const PHASE_TEXT = {
  auction: '競標設施',
  resources: '採購資源',
  building: '擴建網路',
  bureaucracy: '結算供電',
  finished: '終局',
}

/** 玩家席位顏色（依 room.seats 順序） */
export const PLAYER_COLORS = ['#37e6d4', '#9d6bff', '#fbbf24', '#4ade80', '#fb7185', '#f97316']

/**
 * 依座位順序取得玩家顏色（座位在遊戲中不變，顏色因此穩定）。
 * @param {string[]} seats
 * @param {string} id
 */
export function seatColor(seats, id) {
  const index = seats.indexOf(id)
  return PLAYER_COLORS[index >= 0 ? index % PLAYER_COLORS.length : 0]
}

/**
 * game_events → 可讀文字。
 * @param {any} event
 * @param {(id: string) => string} nameOf
 * @param {(city: string) => string} cityName
 */
export function eventText(event, nameOf, cityName) {
  const n = (id) => nameOf(id)
  switch (event.type) {
    case 'game_started':
      return `遊戲開始，啟用叢集：${event.active_regions.join('、')}`
    case 'round_started':
      return `── 第 ${event.round} 回合 ──`
    case 'turn_order_changed':
      return `順位更新：${event.turn_order.map(n).join(' → ')}`
    case 'phase_changed':
      return `進入「${PHASE_TEXT[event.phase] || event.phase}」階段`
    case 'auction_opened':
      return `${n(event.player)} 提名 #${event.plant}（起標 $${event.bid}）`
    case 'bid_placed':
      return `${n(event.player)} 出價 $${event.amount}`
    case 'bid_folded':
      return `${n(event.player)} 退出競價`
    case 'plant_bought':
      return `${n(event.player)} 以 $${event.price} 拿下 #${event.plant}`
    case 'discard_required':
      return `${n(event.player)} 設施超過上限，需棄置一座`
    case 'plant_discarded':
      return `${n(event.player)} 棄置 #${event.plant}${event.resources_lost ? `（溢出 ${event.resources_lost} 資源）` : ''}`
    case 'auction_passed':
      return `${n(event.player)} 本回合不競標`
    case 'resources_bought': {
      const parts = Object.entries(event.quantities)
        .filter(([, qty]) => qty > 0)
        .map(([r, qty]) => `${RESOURCE_META[r]?.icon || r}×${qty}`)
      return `${n(event.player)} 採購 ${parts.join(' ')}（$${event.cost}）`
    }
    case 'resources_skipped':
      return `${n(event.player)} 跳過採購`
    case 'city_built':
      return `${n(event.player)} 佔據 ${cityName(event.city)}（$${event.cost}）`
    case 'build_done':
      return `${n(event.player)} 結束擴建`
    case 'step_changed':
      return `⚡ 進入 Step ${event.step}`
    case 'step3_revealed':
      return '⚡ Step 3 卡現身，牌庫重洗！'
    case 'plant_removed':
      return `#${event.plant} 從市場移除`
    case 'plant_tucked':
      return `#${event.plant} 收入牌庫底`
    case 'power_submitted':
      return `${n(event.player)} 已提交供電計畫`
    case 'powered':
      return `${n(event.player)} 供電 ${event.powered} 節點，收入 $${event.income}`
    case 'resupplied':
      return '資源市場補給完成'
    case 'market_refreshed':
      return '市場補牌'
    case 'final_round':
      return '🏁 終局回合！'
    case 'game_ended':
      return `🏆 ${n(event.winner)} 獲勝！`
    default:
      return null
  }
}
