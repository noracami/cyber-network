// 網格佈局：城市吸附到粗網格（格距＝最小間距保證），連線走水平／垂直折線，
// 捷運圖式呈現。同一條網格線上重疊的線段會像捷運平行線一樣錯開「車道」，
// 靠節點端的小跳段藏在節點圓底下（邊層畫在節點層之下）。
// 佈局是純顯示層，遊戲邏輯（Dijkstra／過路費）仍走原始圖數據，不受影響。
const COLS = 16
const ROWS = 10
const LANE_STEP = 0.08 // 相鄰車道間距（格單位）≈ 14px 世界座標
const LANE_MARGIN = LANE_STEP * 1.5 // 分派車道時的安全邊距：涵蓋轉角過衝，端點相碰也算衝突

const key = (col, row) => `${col},${row}`

/**
 * @param {object} map 地圖靜態數據
 * @returns {{positions: Map<string, {x: number, y: number}>, cells: Map<string, {col: number, row: number}>, occupied: Set<string>, cols: number, rows: number, paths: {x: number, y: number}[][]}}
 */
export function gridLayout(map) {
  /** @type {Map<string, {col: number, row: number}>} */
  const cells = new Map()
  /** @type {Set<string>} */
  const occupied = new Set()

  // 依 id 排序處理，佈局確定性（碰撞時誰讓位是固定的）
  for (const city of [...map.cities].sort((a, b) => a.id.localeCompare(b.id))) {
    const cell = nearestFree(
      Math.round((city.pos.x / 100) * (COLS - 1)),
      Math.round((city.pos.y / 100) * (ROWS - 1)),
      occupied
    )
    occupied.add(key(cell.col, cell.row))
    cells.set(city.id, cell)
  }

  /** @type {Map<string, {x: number, y: number}>} */
  const positions = new Map()
  for (const [id, cell] of cells) {
    positions.set(id, { x: (cell.col / (COLS - 1)) * 100, y: (cell.row / (ROWS - 1)) * 100 })
  }
  return { positions, cells, occupied, cols: COLS, rows: ROWS, paths: routeEdges(map, cells, occupied) }
}

/** 由目標格向外一圈圈找最近的空格（確定性掃描順序） */
function nearestFree(c0, r0, occupied) {
  for (let radius = 0; radius <= COLS + ROWS; radius++) {
    for (let dr = -radius; dr <= radius; dr++) {
      for (let dc = -radius; dc <= radius; dc++) {
        if (Math.max(Math.abs(dc), Math.abs(dr)) !== radius) continue
        const col = c0 + dc
        const row = r0 + dr
        if (col < 0 || col >= COLS || row < 0 || row >= ROWS) continue
        if (!occupied.has(key(col, row))) return { col, row }
      }
    }
  }
  return { col: c0, row: r0 } // 格數遠多於城市數，理論上到不了
}

/**
 * 兩格之間的直角路徑（含端點）。同行同列走直線；
 * 否則比較兩種 L 型，選「彎點與沿途穿過較少節點」的那條。
 */
function orthoPath(a, b, occupied) {
  if (a.col === b.col || a.row === b.row) return [a, b]
  const viaH = { col: b.col, row: a.row } // 先橫後直
  const viaV = { col: a.col, row: b.row } // 先直後橫
  const costOf = (via) =>
    (occupied.has(key(via.col, via.row)) ? 3 : 0) +
    passThroughs(a, via, occupied) +
    passThroughs(via, b, occupied)
  return costOf(viaH) <= costOf(viaV) ? [a, viaH, b] : [a, viaV, b]
}

/** from→to（同行或同列）中間穿過幾個被佔用的格位 */
function passThroughs(from, to, occupied) {
  let count = 0
  if (from.col === to.col) {
    for (let r = Math.min(from.row, to.row) + 1; r < Math.max(from.row, to.row); r++) {
      if (occupied.has(key(from.col, r))) count++
    }
  } else {
    for (let c = Math.min(from.col, to.col) + 1; c < Math.max(from.col, to.col); c++) {
      if (occupied.has(key(c, from.row))) count++
    }
  }
  return count
}

/** 車道序號 → 偏移倍率：0, +1, −1, +2, −2… */
function laneOffset(lane) {
  const multiplier = lane === 0 ? 0 : lane % 2 === 1 ? (lane + 1) / 2 : -(lane / 2)
  return multiplier * LANE_STEP
}

/**
 * 所有邊的折線點（格座標、含車道偏移）。與 map.edges 同序。
 * @returns {{x: number, y: number}[][]}
 */
function routeEdges(map, cells, occupied) {
  const cellPaths = map.edges.map(({ between: [a, b] }) =>
    orthoPath(cells.get(a), cells.get(b), occupied)
  )

  // 線段登記：依（軸向＋網格線）分組
  /** @type {{eIdx: number, sIdx: number, axis: string, from: number, to: number, lane: number}[][]} */
  const segsByEdge = cellPaths.map(() => [])
  /** @type {Map<string, typeof segsByEdge[0]>} */
  const groups = new Map()
  cellPaths.forEach((path, eIdx) => {
    for (let sIdx = 0; sIdx + 1 < path.length; sIdx++) {
      const p = path[sIdx]
      const q = path[sIdx + 1]
      const axis = p.row === q.row ? 'h' : 'v'
      const line = axis === 'h' ? p.row : p.col
      const seg = {
        eIdx,
        sIdx,
        axis,
        line,
        from: axis === 'h' ? Math.min(p.col, q.col) : Math.min(p.row, q.row),
        to: axis === 'h' ? Math.max(p.col, q.col) : Math.max(p.row, q.row),
        lane: 0,
      }
      segsByEdge[eIdx].push(seg)
      const groupKey = axis + line
      if (!groups.has(groupKey)) groups.set(groupKey, [])
      groups.get(groupKey).push(seg)
    }
  })

  // 節點阻擋：線段「穿過」節點（端點停在節點上的不算）時，
  // 保留中央七條車道（±0.24 格），逼它偏到 ±0.32 格 ≈ 57px，
  // 繞出網格模式的節點圓（半徑 44px ≈ 0.25 格）之外
  /** @type {Map<string, {at: number, from: number, to: number}[]>} */
  const blockers = new Map()
  for (const cellKey of occupied) {
    const [col, row] = cellKey.split(',').map(Number)
    for (const [groupKey, at] of [
      ['h' + row, col],
      ['v' + col, row],
    ]) {
      if (!blockers.has(groupKey)) blockers.set(groupKey, [])
      blockers.get(groupKey).push({ at, from: at - 0.3, to: at + 0.3 })
    }
  }

  // 貪婪區間著色：重疊者取最小的空車道
  for (const [groupKey, list] of groups) {
    list.sort((s1, s2) => s1.from - s2.from || s1.to - s2.to)
    const assigned = []
    for (const seg of list) {
      const used = new Set()
      for (const other of assigned) {
        if (seg.from - other.to < LANE_MARGIN && other.from - seg.to < LANE_MARGIN) {
          used.add(other.lane)
        }
      }
      for (const blocker of blockers.get(groupKey) || []) {
        if (blocker.at === seg.from || blocker.at === seg.to) continue // 自己的端點
        if (seg.from < blocker.to && seg.to > blocker.from) {
          for (let lane = 0; lane <= 6; lane++) used.add(lane)
        }
      }
      let lane = 0
      while (used.has(lane)) lane++
      seg.lane = lane
      assigned.push(seg)
    }
  }

  // 產出折線：每段沿自己的（偏移後）線座標走，段與段在偏移線交點轉彎，
  // 節點端的垂直小跳段落在節點圓覆蓋範圍內。
  // 繞節點的大偏移段（escape）在節點端多折一個 Z：先順行進方向縮進 INSET
  // 再橫移出去，避免連接段躺在節點所在的網格線上壓到別的邊。
  const ESCAPE = 0.25
  const INSET = 0.2
  return cellPaths.map((path, eIdx) => {
    const segs = segsByEdge[eIdx]
    const start = { x: path[0].col, y: path[0].row }
    const end = { x: path[path.length - 1].col, y: path[path.length - 1].row }
    /** @type {{x: number, y: number}[]} */
    const points = [start]
    let cursor = start
    segs.forEach((seg, i) => {
      const next = segs[i + 1]
      const offset = laneOffset(seg.lane)
      const coord = seg.line + offset
      const escape = Math.abs(offset) > ESCAPE
      if (seg.axis === 'h') {
        const exitX = next ? next.line + laneOffset(next.lane) : end.x
        const dir = Math.sign(exitX - cursor.x) || 1
        if (escape && i === 0) {
          points.push({ x: cursor.x + dir * INSET, y: cursor.y }, { x: cursor.x + dir * INSET, y: coord })
        } else {
          points.push({ x: cursor.x, y: coord })
        }
        if (escape && !next) {
          points.push({ x: exitX - dir * INSET, y: coord }, { x: exitX - dir * INSET, y: end.y })
          cursor = { x: exitX - dir * INSET, y: end.y }
        } else {
          points.push({ x: exitX, y: coord })
          cursor = { x: exitX, y: coord }
        }
      } else {
        const exitY = next ? next.line + laneOffset(next.lane) : end.y
        const dir = Math.sign(exitY - cursor.y) || 1
        if (escape && i === 0) {
          points.push({ x: cursor.x, y: cursor.y + dir * INSET }, { x: coord, y: cursor.y + dir * INSET })
        } else {
          points.push({ x: coord, y: cursor.y })
        }
        if (escape && !next) {
          points.push({ x: coord, y: exitY - dir * INSET }, { x: end.x, y: exitY - dir * INSET })
          cursor = { x: end.x, y: exitY - dir * INSET }
        } else {
          points.push({ x: coord, y: exitY })
          cursor = { x: coord, y: exitY }
        }
      }
    })
    points.push(end)
    return points.filter(
      (p, i, all) => i === 0 || Math.abs(p.x - all[i - 1].x) > 1e-9 || Math.abs(p.y - all[i - 1].y) > 1e-9
    )
  })
}
