// PixiJS 地圖渲染器（M5 佔位美術：向量幾何風，之後可整體換皮）。
// M9：固定世界座標 1600×1000＋手刻 pan/zoom——鏡頭掛在 viewport 容器上，
// state 更新只全量重繪 root、不碰鏡頭，兩者互不干擾。
import { Application, Container, Graphics, Text } from 'pixi.js'

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
    this.root = null
    this.props = null
    /** @type {Map<number, {x: number, y: number, sx: number, sy: number}>} */
    this.pointers = new Map()
    this.moved = false
    this.pinchBase = null
  }

  /** @param {HTMLElement} host */
  async init(host) {
    this.app = new Application()
    await this.app.init({ backgroundAlpha: 0, resizeTo: host, antialias: true })
    host.appendChild(this.app.canvas)
    this.viewport = new Container()
    this.root = new Container()
    this.viewport.addChild(this.root)
    this.app.stage.addChild(this.viewport)
    this.bindNavigation()
    this.app.renderer.on('resize', () => {
      this.fitView()
      this.redraw()
    })
    this.fitView()
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
    canvas.style.touchAction = 'none'

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
    const { map, game, colorOf, buildableCost, onCityTap, onHover } = this.props

    for (const child of this.root.removeChildren()) child.destroy({ children: true })

    const sx = (x) => PAD + (x / 100) * (WORLD.w - PAD * 2)
    const sy = (y) => PAD + (y / 100) * (WORLD.h - PAD * 2)

    const cityById = new Map(map.cities.map((c) => [c.id, c]))
    const regionColor = new Map(map.regions.map((r) => [r.id, r.color]))
    const active = new Set(game.active_regions)

    const edgeLayer = new Container()
    const cityLayer = new Container()
    this.root.addChild(edgeLayer, cityLayer)

    // 邊與過路費
    for (const { between: [a, b], cost } of map.edges) {
      const ca = cityById.get(a)
      const cb = cityById.get(b)
      const dim = !active.has(ca.region) || !active.has(cb.region)

      const line = new Graphics()
      line
        .moveTo(sx(ca.pos.x), sy(ca.pos.y))
        .lineTo(sx(cb.pos.x), sy(cb.pos.y))
        .stroke({ width: 3, color: 0x263054, alpha: dim ? 0.2 : 1 })
      edgeLayer.addChild(line)

      if (!dim) {
        const label = new Text({
          text: String(cost),
          style: { fontSize: 14, fill: 0x6b7699 },
          resolution: 2,
        })
        label.anchor.set(0.5)
        label.position.set((sx(ca.pos.x) + sx(cb.pos.x)) / 2, (sy(ca.pos.y) + sy(cb.pos.y)) / 2)
        edgeLayer.addChild(label)
      }
    }

    // 城市節點
    for (const city of map.cities) {
      const isActive = active.has(city.region)
      const owners = game.city_owners[city.id] || []
      const cost = isActive ? buildableCost(city.id) : null

      const node = new Container()
      node.position.set(sx(city.pos.x), sy(city.pos.y))
      node.alpha = isActive ? 1 : 0.15

      const circle = new Graphics()
      circle
        .circle(0, 0, 24)
        .fill(0x121627)
        .circle(0, 0, 24)
        .stroke({
          width: cost != null ? 4 : 2.5,
          color: cost != null ? 0x37e6d4 : regionColor.get(city.region),
        })
      node.addChild(circle)

      owners.forEach((ownerId, index) => {
        const pip = new Graphics()
        pip.circle(-11 + index * 11, 0, 5).fill(colorOf(ownerId))
        node.addChild(pip)
      })

      const label = new Text({
        text: city.name,
        style: { fontSize: 16, fill: 0xb8c2e0 },
        resolution: 2,
      })
      label.anchor.set(0.5, 0)
      label.position.set(0, 28)
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
