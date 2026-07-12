// PixiJS 地圖渲染器（M5 佔位美術：向量幾何風，之後可整體換皮）。
// M9：固定世界座標 1600×1000＋手刻 pan/zoom——鏡頭掛在 viewport 容器上，
// state 更新只全量重繪 root、不碰鏡頭，兩者互不干擾。
import { Application, Container, Graphics, Text } from 'pixi.js'
import { mulberry32 } from './rng'

// 世界尺寸由數據反推：最擠的城市對（new_york↔philadelphia，3.61 單位）
// 在此尺寸下間距 ~72px，大於節點直徑 48px——放大到底也不會疊
const WORLD = { w: 2800, h: 1750 }
const PAD = 60
const ZOOM_MAX = 4.5 // 相對 fit 的最大倍率；最小 = fit（不可縮到比全圖更遠）
const TAP_SLOP = 8 // 累計位移超過此值視為拖曳，抑制節點點擊

export class MapBoard {
  constructor() {
    /** @type {Application | null} */
    this.app = null
    this.viewport = null
    this.bgLayer = null
    this.root = null
    this.fxLayer = null
    this.props = null
    /** @type {{node: import('pixi.js').Container, age: number, delay: number, duration: number, update: (t: number) => void, screen?: boolean}[]} */
    this.fx = []
    this.reducedMotion =
      typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
    /** redraw 時快取，供事件動畫定位 */
    this.cityPos = new Map()
    this.edgePts = []
    this.edgeByPair = new Map()
    this.lastS = null
    /** 可建節點的呼吸燈環（redraw 重建） */
    this.breathGlows = []
    this.animTime = 0
    /** 擴建確認中的路徑動畫（持續循環，clearRoute 收掉） */
    this.routeFx = null
    /** @type {Map<number, {x: number, y: number, sx: number, sy: number}>} */
    this.pointers = new Map()
    this.moved = false
    this.pinchBase = null
    /** 縮放平移開關（預設關；MapBoard 依使用者設定切換） */
    this.navEnabled = false
  }

  /** @param {boolean} enabled 關閉時回到全覽並把觸控行為還給頁面捲動 */
  setNav(enabled) {
    this.navEnabled = enabled
    if (this.app) this.app.canvas.style.touchAction = enabled ? 'none' : 'auto'
    if (!enabled) this.fitView()
  }

  /** @param {HTMLElement} host */
  async init(host) {
    this.app = new Application()
    await this.app.init({ backgroundAlpha: 0, resizeTo: host, antialias: true })
    host.appendChild(this.app.canvas)
    this.viewport = new Container()
    this.bgLayer = new Container()
    this.root = new Container()
    this.fxLayer = new Container()
    this.viewport.addChild(this.bgLayer, this.root, this.fxLayer)
    this.app.stage.addChild(this.viewport)
    this.drawBackground()
    this.app.ticker.add((ticker) => this.updateFx(ticker.deltaMS))
    this.bindNavigation()
    this.app.renderer.on('resize', () => {
      this.fitView()
      this.redraw()
    })
    this.fitView()
  }

  /** 電路板紋理背景（固定 seed，只畫一次；跟著鏡頭縮放平移） */
  drawBackground() {
    const g = new Graphics()
    const rand = mulberry32(1337)

    // 低對比格點
    for (let x = PAD; x <= WORLD.w - PAD; x += 100) {
      for (let y = PAD; y <= WORLD.h - PAD; y += 100) {
        g.circle(x, y, 1.6).fill({ color: 0x37e6d4, alpha: 0.05 })
      }
    }

    // 稀疏走線＋端點 via
    for (let i = 0; i < 26; i++) {
      let x = rand() * WORLD.w
      let y = rand() * WORLD.h
      g.moveTo(x, y)
      const steps = 2 + Math.floor(rand() * 3)
      for (let s = 0; s < steps; s++) {
        if (rand() < 0.5) x = Math.max(0, Math.min(WORLD.w, x + (rand() - 0.5) * 700))
        else y = Math.max(0, Math.min(WORLD.h, y + (rand() - 0.5) * 500))
        g.lineTo(x, y)
      }
      g.stroke({ width: 2, color: rand() < 0.3 ? 0x9d6bff : 0x37e6d4, alpha: 0.05 })
      g.circle(x, y, 3).fill({ color: 0x37e6d4, alpha: 0.07 })
    }

    this.bgLayer.addChild(g)
  }

  update(props) {
    this.props = props
    this.redraw()
  }

  // ── 鏡頭 ──────────────────────────────

  fitScale() {
    return Math.min(this.app.screen.width / WORLD.w, this.app.screen.height / WORLD.h)
  }

  /** 全圖置中（初始與「全圖」按鈕） */
  fitView() {
    if (!this.app) return
    const s = this.fitScale()
    this.viewport.scale.set(s)
    this.viewport.position.set(
      (this.app.screen.width - WORLD.w * s) / 2,
      (this.app.screen.height - WORLD.h * s) / 2
    )
  }

  resetView() {
    this.fitView()
  }

  /** 地圖比畫面小就置中，比畫面大就不許拖出邊界 */
  clampView() {
    const { width, height } = this.app.screen
    const s = this.viewport.scale.x
    const w = WORLD.w * s
    const h = WORLD.h * s
    this.viewport.x = w <= width ? (width - w) / 2 : Math.min(0, Math.max(width - w, this.viewport.x))
    this.viewport.y = h <= height ? (height - h) / 2 : Math.min(0, Math.max(height - h, this.viewport.y))
  }

  /**
   * 以畫布座標 (cx, cy) 為錨點縮放——錨點下方的地圖位置保持不動。
   * @param {number} cx @param {number} cy @param {number} target
   */
  zoomAt(cx, cy, target) {
    const fit = this.fitScale()
    const next = Math.min(fit * ZOOM_MAX, Math.max(fit, target))
    const prev = this.viewport.scale.x
    this.viewport.x = cx - ((cx - this.viewport.x) * next) / prev
    this.viewport.y = cy - ((cy - this.viewport.y) * next) / prev
    this.viewport.scale.set(next)
    this.clampView()
  }

  pinch() {
    const [a, b] = [...this.pointers.values()]
    return {
      dist: Math.hypot(a.x - b.x, a.y - b.y),
      midX: (a.x + b.x) / 2,
      midY: (a.y + b.y) / 2,
      scale: this.viewport.scale.x,
      x: this.viewport.x,
      y: this.viewport.y,
    }
  }

  /** 拖曳平移＋滾輪縮放＋雙指 pinch，DOM pointer 事件實作；節點點擊仍走 Pixi 事件 */
  bindNavigation() {
    const canvas = this.app.canvas
    canvas.style.touchAction = this.navEnabled ? 'none' : 'auto'

    canvas.addEventListener('pointerdown', (event) => {
      canvas.setPointerCapture(event.pointerId)
      this.pointers.set(event.pointerId, {
        x: event.clientX,
        y: event.clientY,
        sx: event.clientX,
        sy: event.clientY,
      })
      this.moved = false
      this.pinchBase = this.pointers.size === 2 ? this.pinch() : null
    })

    canvas.addEventListener('pointermove', (event) => {
      const pointer = this.pointers.get(event.pointerId)
      if (!pointer) return
      const dx = event.clientX - pointer.x
      const dy = event.clientY - pointer.y
      pointer.x = event.clientX
      pointer.y = event.clientY
      if (Math.abs(pointer.x - pointer.sx) + Math.abs(pointer.y - pointer.sy) > TAP_SLOP) {
        this.moved = true
      }

      if (!this.navEnabled) return

      if (this.pointers.size === 1) {
        this.viewport.x += dx
        this.viewport.y += dy
        this.clampView()
      } else if (this.pointers.size === 2 && this.pinchBase) {
        const now = this.pinch()
        const rect = canvas.getBoundingClientRect()
        // 回到 pinch 起點的鏡頭，套用中點平移，再以目前中點為錨縮放
        this.viewport.scale.set(this.pinchBase.scale)
        this.viewport.position.set(
          this.pinchBase.x + (now.midX - this.pinchBase.midX),
          this.pinchBase.y + (now.midY - this.pinchBase.midY)
        )
        const target = this.pinchBase.scale * (this.pinchBase.dist ? now.dist / this.pinchBase.dist : 1)
        this.zoomAt(now.midX - rect.left, now.midY - rect.top, target)
      }
    })

    const release = (event) => {
      this.pointers.delete(event.pointerId)
      this.pinchBase = null
    }
    canvas.addEventListener('pointerup', release)
    canvas.addEventListener('pointercancel', release)

    canvas.addEventListener(
      'wheel',
      (event) => {
        if (!this.navEnabled) return // 不吃事件，滾輪還給頁面捲動
        event.preventDefault()
        const factor = Math.exp(-event.deltaY * 0.0015)
        this.zoomAt(event.offsetX, event.offsetY, this.viewport.scale.x * factor)
      },
      { passive: false }
    )
  }

  // ── 繪製 ──────────────────────────────

  redraw() {
    if (!this.app || !this.props) return
    const { map, game, colorOf, buildableCost, onCityTap, onHover, layout } = this.props

    for (const child of this.root.removeChildren()) child.destroy({ children: true })

    const sx = (x) => PAD + (x / 100) * (WORLD.w - PAD * 2)
    const sy = (y) => PAD + (y / 100) * (WORLD.h - PAD * 2)
    // 網格佈局時城市座標換成吸附後的位置；地理佈局用原始數據
    const posOf = (city) => (layout ? layout.positions.get(city.id) : city.pos)
    // 網格模式間距寬裕（~178px），節點與線都放大一階；
    // 地理模式受最擠城市對（72px）限制，維持較小尺寸
    const S = layout
      ? { r: 44, edgeW: 10, nameSize: 18, nameY: 52, costSize: 20 }
      : { r: 24, edgeW: 8, nameSize: 16, nameY: 28, costSize: 18 }

    const cityById = new Map(map.cities.map((c) => [c.id, c]))
    const regionColor = new Map(map.regions.map((r) => [r.id, r.color]))
    const active = new Set(game.active_regions)

    // 快取世界座標與尺寸，供事件動畫（playEvents）定位
    this.lastS = S
    this.cityPos = new Map(
      map.cities.map((c) => [c.id, { x: sx(posOf(c).x), y: sy(posOf(c).y) }])
    )
    this.edgePts = []
    this.edgeLabelPos = []
    this.edgeByPair = new Map(
      map.edges.map(({ between: [a, b] }, index) => [[a, b].sort().join('|'), index])
    )
    this.breathGlows = []

    const edgeLayer = new Container()
    const cityLayer = new Container()
    this.root.addChild(edgeLayer, cityLayer)

    // 邊與過路費
    map.edges.forEach(({ between: [a, b], cost }, edgeIndex) => {
      const ca = cityById.get(a)
      const cb = cityById.get(b)
      const dim = !active.has(ca.region) || !active.has(cb.region)

      // 折點序列：地理模式是兩端直線；網格模式走水平／垂直折線（含車道錯開）
      const points = layout
        ? layout.paths[edgeIndex].map((p) => ({
            x: sx((p.x / (layout.cols - 1)) * 100),
            y: sy((p.y / (layout.rows - 1)) * 100),
          }))
        : [ca.pos, cb.pos].map((p) => ({ x: sx(p.x), y: sy(p.y) }))
      this.edgePts[edgeIndex] = points

      // 走線質感：底線＋較亮的細芯線
      const line = new Graphics()
      line.moveTo(points[0].x, points[0].y)
      for (const point of points.slice(1)) line.lineTo(point.x, point.y)
      line.stroke({ width: S.edgeW, color: 0x263054, alpha: dim ? 0.2 : 1, join: 'round' })
      const core = new Graphics()
      core.moveTo(points[0].x, points[0].y)
      for (const point of points.slice(1)) core.lineTo(point.x, point.y)
      core.stroke({
        width: Math.max(1.5, S.edgeW * 0.28),
        color: 0x4a5a8f,
        alpha: dim ? 0.12 : 0.85,
        join: 'round',
      })
      edgeLayer.addChild(line, core)

      if (!dim) {
        // 過路費標在最長線段的中點，配半透明底板
        let best = null
        for (let i = 1; i < points.length; i++) {
          const len = Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
          if (!best || len > best.len) {
            best = {
              len,
              x: (points[i].x + points[i - 1].x) / 2,
              y: (points[i].y + points[i - 1].y) / 2,
            }
          }
        }
        this.edgeLabelPos[edgeIndex] = { x: best.x, y: best.y }
        const label = new Text({
          text: String(cost),
          style: { fontSize: S.costSize, fill: 0x8a95bd },
          resolution: 2,
        })
        label.anchor.set(0.5)
        label.position.set(best.x, best.y)
        const plate = new Graphics()
        plate
          .roundRect(best.x - label.width / 2 - 5, best.y - label.height / 2 - 2, label.width + 10, label.height + 4, 4)
          .fill({ color: 0x0b0e17, alpha: 0.78 })
        edgeLayer.addChild(plate, label)
      }
    })

    // 城市節點：切角晶片章＋針腳＋插槽燈（插槽數＝當前 Step 開放的進駐位）
    const chipPath = (g, r, c) => {
      g.moveTo(-r + c, -r)
        .lineTo(r - c, -r)
        .lineTo(r, -r + c)
        .lineTo(r, r - c)
        .lineTo(r - c, r)
        .lineTo(-r + c, r)
        .lineTo(-r, r - c)
        .lineTo(-r, -r + c)
        .closePath()
    }

    for (const city of map.cities) {
      const isActive = active.has(city.region)
      const owners = game.city_owners[city.id] || []
      const cost = isActive ? buildableCost(city.id) : null
      const rColor = regionColor.get(city.region)

      const node = new Container()
      node.position.set(sx(posOf(city).x), sy(posOf(city).y))
      node.alpha = isActive ? 1 : 0.15

      const chamfer = S.r * 0.38
      const g = new Graphics()
      if (cost != null) {
        // 可建目標：外圈光暈（獨立 Graphics，ticker 驅動呼吸）
        const glow = new Graphics()
        chipPath(glow, S.r + S.r * 0.16, chamfer * 1.16)
        glow.stroke({ width: S.r * 0.09, color: 0x37e6d4 })
        glow.alpha = 0.3
        node.addChild(glow)
        this.breathGlows.push(glow)
      }
      chipPath(g, S.r, chamfer)
      g.fill(0x121627)
      chipPath(g, S.r, chamfer)
      g.stroke({
        width: cost != null ? S.r * 0.1 : S.r * 0.06,
        color: cost != null ? 0x37e6d4 : rColor,
      })
      // 針腳（四邊各二）
      const pin = S.r * 0.16
      for (const off of [-S.r * 0.42, S.r * 0.42]) {
        g.moveTo(off, -S.r).lineTo(off, -S.r - pin)
        g.moveTo(off, S.r).lineTo(off, S.r + pin)
        g.moveTo(-S.r, off).lineTo(-S.r - pin, off)
        g.moveTo(S.r, off).lineTo(S.r + pin, off)
      }
      g.stroke({ width: Math.max(1.5, S.r * 0.05), color: rColor, alpha: 0.55 })
      node.addChild(g)

      // 插槽燈：開放位（依 Step）為暗槽，佔據者亮玩家色
      const slotSize = S.r * 0.42
      const slotGap = slotSize * 0.42
      const slotCount = game.step
      const totalW = slotCount * slotSize + (slotCount - 1) * slotGap
      const sg = new Graphics()
      for (let i = 0; i < slotCount; i++) {
        const x = -totalW / 2 + i * (slotSize + slotGap)
        sg.roundRect(x, -slotSize / 2, slotSize, slotSize, slotSize * 0.2)
        if (owners[i]) {
          sg.fill(colorOf(owners[i]))
        } else {
          sg.fill(0x0b0e17)
          sg.roundRect(x, -slotSize / 2, slotSize, slotSize, slotSize * 0.2)
          sg.stroke({ width: 1.2, color: 0x2c3760 })
        }
      }
      node.addChild(sg)

      const label = new Text({
        text: city.name,
        style: { fontSize: S.nameSize, fill: 0xb8c2e0 },
        resolution: 2,
      })
      label.anchor.set(0.5, 0)
      label.position.set(0, S.nameY + S.r * 0.18)
      node.addChild(label)

      if (isActive) {
        node.eventMode = 'static'
        node.cursor = cost != null ? 'pointer' : 'default'
        node.on('pointertap', () => {
          if (!this.moved) onCityTap(city.id)
        })
        node.on('pointerover', (event) => onHover(city.id, event.global.x, event.global.y))
        node.on('pointerout', () => onHover(null, 0, 0))
      }

      cityLayer.addChild(node)
    }
  }

  // ── 事件動畫（A3）：一次性特效，prefers-reduced-motion 時全部跳過 ──

  /** @param {object[]} events game_events 批次 */
  playEvents(events) {
    if (!this.app || !this.props || this.reducedMotion) return
    const { colorOf } = this.props
    for (const event of events) {
      switch (event.type) {
        case 'city_built':
          // 三連波，體感上才注意得到
          for (let echo = 0; echo < 3; echo++) {
            this.fxPulseCity(event.city, colorOf(event.player), echo * 300)
          }
          break
        case 'powered':
          this.fxPowered(event.player)
          break
        case 'step_changed':
          this.fxScanline(0x37e6d4)
          break
        case 'step3_revealed':
          this.fxScanline(0xff5470)
          break
      }
    }
  }

  /** 節點擴散波（晶片形回聲） */
  fxPulseCity(cityId, color, delay) {
    const pos = this.cityPos.get(cityId)
    const S = this.lastS
    if (!pos || !S) return
    const r = S.r
    const c = r * 0.38
    const ring = new Graphics()
    ring
      .moveTo(-r + c, -r)
      .lineTo(r - c, -r)
      .lineTo(r, -r + c)
      .lineTo(r, r - c)
      .lineTo(r - c, r)
      .lineTo(-r + c, r)
      .lineTo(-r, r - c)
      .lineTo(-r, -r + c)
      .closePath()
      .stroke({ width: Math.max(3, r * 0.11), color })
    ring.position.set(pos.x, pos.y)
    this.addFx({
      node: ring,
      delay,
      duration: 650,
      update(t) {
        ring.scale.set(1 + t * 1.1)
        ring.alpha = (1 - t) * 0.95
      },
    })
  }

  /** 供電結算：玩家的城市依序脈衝，城市間直連線路跑電流光點——整波三連播 */
  fxPowered(playerId) {
    const { game, map, colorOf } = this.props
    const cities = game.players[playerId]?.cities || []
    if (cities.length === 0) return
    const color = colorOf(playerId)
    const owned = new Set(cities)

    for (let wave = 0; wave < 3; wave++) {
      const base = wave * 850
      cities.forEach((cityId, index) => this.fxPulseCity(cityId, color, base + index * 90))
      map.edges.forEach(({ between: [a, b] }, edgeIndex) => {
        if (!owned.has(a) || !owned.has(b)) return
        const points = this.edgePts[edgeIndex]
        if (points) this.fxCurrent(points, color, base + 150)
      })
    }
  }

  /** 沿折線跑一顆電流光點（含小尾跡） */
  fxCurrent(points, color, delay) {
    const lengths = []
    let total = 0
    for (let i = 1; i < points.length; i++) {
      total += Math.hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
      lengths.push(total)
    }
    if (total === 0) return

    const at = (t) => {
      const d = t * total
      let i = 0
      while (i < lengths.length - 1 && lengths[i] < d) i++
      const start = i === 0 ? 0 : lengths[i - 1]
      const f = (d - start) / (lengths[i] - start || 1)
      const p = points[i]
      const q = points[i + 1]
      return { x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f }
    }

    const base = Math.max(6, (this.lastS?.r || 30) * 0.17)
    const node = new Container()
    // 外圈光暈＋主點＋兩節尾跡
    const glow = new Graphics()
    glow.circle(0, 0, base * 2.1).fill({ color, alpha: 0.18 })
    node.addChild(glow)
    const dots = [1, 0.5, 0.25].map((alpha, index) => {
      const dot = new Graphics()
      dot.circle(0, 0, base - index * base * 0.25).fill({ color, alpha })
      node.addChild(dot)
      return dot
    })
    dots.unshift(glow)
    this.addFx({
      node,
      delay,
      duration: Math.max(450, total * 1.1),
      update(t) {
        dots.forEach((dot, index) => {
          const p = at(Math.max(0, t - index * 0.045))
          dot.position.set(p.x, p.y)
        })
        node.alpha = t > 0.85 ? (1 - t) / 0.15 : 1
      },
    })
  }

  /** 全版掃描線過場（螢幕空間，Step 切換用） */
  fxScanline(color) {
    const { width, height } = this.app.screen
    const node = new Container()
    const body = new Graphics()
    body.rect(0, -70, width, 70).fill({ color, alpha: 0.08 })
    const edge = new Graphics()
    edge.rect(0, 0, width, 2.5).fill({ color, alpha: 0.55 })
    node.addChild(body, edge)
    this.addFx({
      node,
      delay: 0,
      duration: 750,
      screen: true,
      update(t) {
        node.y = -70 + t * (height + 140)
      },
    })
  }

  addFx(fx) {
    if (this.reducedMotion) return
    fx.age = 0
    fx.node.visible = fx.delay <= 0
    ;(fx.screen ? this.app.stage : this.fxLayer).addChild(fx.node)
    this.fx.push(fx)
  }

  /**
   * 擴建確認：高亮路徑連線、循環電流、路徑過路費放大 4 倍、
   * 目的地掛進場費標籤——直到 clearRoute。
   * @param {string[]} pathCityIds
   * @param {string} color 玩家座色
   * @param {string} targetId 目的城市
   * @param {number} entryFee 進場費（$10/15/20）
   */
  showRoute(pathCityIds, color, targetId, entryFee) {
    this.clearRoute()
    if (this.reducedMotion || !this.fxLayer || !this.lastS) return
    const S = this.lastS
    const node = new Container()

    /** 已放置的大標籤範圍（供進場標籤避讓） */
    const placedRects = []
    const intersects = (a, b) =>
      a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y

    const bigLabel = (text, x, y, fill) => {
      const label = new Text({
        text,
        style: { fontSize: S.costSize * 4, fill, fontWeight: 'bold' },
        resolution: 2,
      })
      label.anchor.set(0.5)
      label.position.set(x, y)
      const w = label.width + 28
      const h = label.height + 12
      const plate = new Graphics()
      plate
        .roundRect(x - w / 2, y - h / 2, w, h, 12)
        .fill({ color: 0x0b0e17, alpha: 0.88 })
        .roundRect(x - w / 2, y - h / 2, w, h, 12)
        .stroke({ width: 2, color: fill, alpha: 0.5 })
      node.addChild(plate, label)
      const rect = { x: x - w / 2, y: y - h / 2, w, h }
      placedRects.push(rect)
      return { label, w, h }
    }

    // 路徑城市序列 → 各邊折線（依行進方向定向）→ 串成一條完整折線
    const full = []
    for (let i = 1; i < pathCityIds.length; i++) {
      const [a, b] = [pathCityIds[i - 1], pathCityIds[i]]
      const index = this.edgeByPair.get([a, b].sort().join('|'))
      const pts = this.edgePts[index]
      if (!pts) continue
      const start = this.cityPos.get(a)
      const forward =
        Math.hypot(pts[0].x - start.x, pts[0].y - start.y) <=
        Math.hypot(pts[pts.length - 1].x - start.x, pts[pts.length - 1].y - start.y)
      const oriented = forward ? pts : [...pts].reverse()
      for (const p of oriented) {
        const last = full[full.length - 1]
        if (!last || last.x !== p.x || last.y !== p.y) full.push(p)
      }
      const line = new Graphics()
      line.moveTo(oriented[0].x, oriented[0].y)
      for (const p of oriented.slice(1)) line.lineTo(p.x, p.y)
      line.stroke({ width: S.r * 0.14, color, alpha: 0.4, join: 'round' })
      node.addChild(line)

      // 路徑上的過路費放大 4 倍
      const labelPos = this.edgeLabelPos[index]
      if (labelPos) bigLabel(String(this.props.map.edges[index].cost), labelPos.x, labelPos.y, 0xfbbf24)
    }

    // 目的地進場費（$10/15/20）：優先沿最後一段路徑的延伸方向放
    // （過路費標籤都在路徑上，反向延伸天然錯開），撞到再換上下左右
    const target = this.cityPos.get(targetId)
    if (target && entryFee != null) {
      const offset = S.r * 2.6
      const candidates = []
      if (full.length >= 2) {
        const p = full[full.length - 2]
        const len = Math.hypot(target.x - p.x, target.y - p.y) || 1
        candidates.push({
          x: target.x + ((target.x - p.x) / len) * offset,
          y: target.y + ((target.y - p.y) / len) * offset,
        })
      }
      candidates.push(
        { x: target.x, y: target.y - offset },
        { x: target.x, y: target.y + offset },
        { x: target.x + offset * 1.4, y: target.y },
        { x: target.x - offset * 1.4, y: target.y }
      )

      // 用暫測文字量尺寸，挑第一個不與過路費標籤重疊的位置
      const probe = new Text({
        text: `進場 $${entryFee}`,
        style: { fontSize: S.costSize * 4, fontWeight: 'bold' },
        resolution: 2,
      })
      const w = probe.width + 28
      const h = probe.height + 12
      probe.destroy()
      const spot =
        candidates.find((c) =>
          placedRects.every((r) => !intersects({ x: c.x - w / 2, y: c.y - h / 2, w, h }, r))
        ) || candidates[0]
      bigLabel(`進場 $${entryFee}`, spot.x, spot.y, 0x37e6d4)
    }

    // 循環電流光點（有路徑才有）
    let dot = null
    let lengths = []
    let total = 0
    let duration = 1
    if (full.length >= 2) {
      const base = Math.max(6, S.r * 0.17)
      dot = new Graphics()
      dot.circle(0, 0, base * 1.9).fill({ color, alpha: 0.2 })
      dot.circle(0, 0, base).fill({ color, alpha: 1 })
      node.addChild(dot)
      for (let i = 1; i < full.length; i++) {
        total += Math.hypot(full[i].x - full[i - 1].x, full[i].y - full[i - 1].y)
        lengths.push(total)
      }
      duration = Math.max(700, total * 1.2)
    }

    if (node.children.length === 0) {
      node.destroy({ children: true })
      return
    }

    this.fxLayer.addChild(node)
    this.routeFx = {
      node,
      age: 0,
      update: (age) => {
        if (!dot) return
        const t = (age % duration) / duration
        const d = t * total
        let i = 0
        while (i < lengths.length - 1 && lengths[i] < d) i++
        const start = i === 0 ? 0 : lengths[i - 1]
        const f = (d - start) / (lengths[i] - start || 1)
        const p = full[i]
        const q = full[i + 1]
        dot.position.set(p.x + (q.x - p.x) * f, p.y + (q.y - p.y) * f)
      },
    }
  }

  clearRoute() {
    if (!this.routeFx) return
    this.routeFx.node.parent?.removeChild(this.routeFx.node)
    this.routeFx.node.destroy({ children: true })
    this.routeFx = null
  }

  updateFx(deltaMS) {
    // 可建節點呼吸燈（1.4s 週期）
    this.animTime += deltaMS
    if (this.breathGlows.length > 0 && !this.reducedMotion) {
      const alpha = 0.16 + 0.2 * (0.5 + 0.5 * Math.sin((this.animTime / 1400) * Math.PI * 2))
      for (const glow of this.breathGlows) {
        if (!glow.destroyed) glow.alpha = alpha
      }
    }

    // 路徑循環動畫
    if (this.routeFx) {
      this.routeFx.age += deltaMS
      this.routeFx.update(this.routeFx.age)
    }

    if (this.fx.length === 0) return
    for (const fx of [...this.fx]) {
      if (fx.delay > 0) {
        fx.delay -= deltaMS
        continue
      }
      fx.node.visible = true
      fx.age += deltaMS
      const t = Math.min(1, fx.age / fx.duration)
      fx.update(t)
      if (t >= 1) {
        fx.node.parent?.removeChild(fx.node)
        fx.node.destroy({ children: true })
        this.fx.splice(this.fx.indexOf(fx), 1)
      }
    }
  }

  destroy() {
    this.fx = []
    this.routeFx = null
    this.breathGlows = []
    this.app?.destroy(true, { children: true, texture: true })
    this.app = null
    this.props = null
  }
}
