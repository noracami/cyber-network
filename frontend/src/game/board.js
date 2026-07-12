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
    this.props = null
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
    this.viewport.addChild(this.bgLayer, this.root)
    this.app.stage.addChild(this.viewport)
    this.drawBackground()
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
        // 可建目標：外圈微光暈
        chipPath(g, S.r + S.r * 0.16, chamfer * 1.16)
        g.stroke({ width: S.r * 0.09, color: 0x37e6d4, alpha: 0.3 })
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

  destroy() {
    this.app?.destroy(true, { children: true, texture: true })
    this.app = null
    this.props = null
  }
}
