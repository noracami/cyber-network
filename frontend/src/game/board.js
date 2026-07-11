// PixiJS 地圖渲染器（M5 佔位美術：向量幾何風，之後可整體換皮）。
// 每次 state 更新全量重繪——42 節點＋87 邊的規模下這是最簡單也夠快的策略。
import { Application, Container, Graphics, Text } from 'pixi.js'

const PAD = 36

export class MapBoard {
  constructor() {
    /** @type {Application | null} */
    this.app = null
    this.root = null
    this.props = null
  }

  /** @param {HTMLElement} host */
  async init(host) {
    this.app = new Application()
    await this.app.init({ backgroundAlpha: 0, resizeTo: host, antialias: true })
    host.appendChild(this.app.canvas)
    this.root = new Container()
    this.app.stage.addChild(this.root)
    this.app.renderer.on('resize', () => this.redraw())
  }

  update(props) {
    this.props = props
    this.redraw()
  }

  redraw() {
    if (!this.app || !this.props) return
    const { map, game, colorOf, buildableCost, onCityTap, onHover } = this.props

    for (const child of this.root.removeChildren()) child.destroy({ children: true })

    const width = this.app.screen.width
    const height = this.app.screen.height
    const sx = (x) => PAD + (x / 100) * (width - PAD * 2)
    const sy = (y) => PAD + (y / 100) * (height - PAD * 2)

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
        .stroke({ width: 1.5, color: 0x263054, alpha: dim ? 0.2 : 1 })
      edgeLayer.addChild(line)

      if (!dim) {
        const label = new Text({ text: String(cost), style: { fontSize: 9, fill: 0x6b7699 } })
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
        .circle(0, 0, 13)
        .fill(0x121627)
        .circle(0, 0, 13)
        .stroke({
          width: cost != null ? 2.5 : 1.5,
          color: cost != null ? 0x37e6d4 : regionColor.get(city.region),
        })
      node.addChild(circle)

      owners.forEach((ownerId, index) => {
        const pip = new Graphics()
        pip.circle(-7 + index * 7, 0, 3.2).fill(colorOf(ownerId))
        node.addChild(pip)
      })

      const label = new Text({ text: city.name, style: { fontSize: 10, fill: 0xb8c2e0 } })
      label.anchor.set(0.5, 0)
      label.position.set(0, 16)
      node.addChild(label)

      if (isActive) {
        node.eventMode = 'static'
        node.cursor = cost != null ? 'pointer' : 'default'
        node.on('pointertap', () => onCityTap(city.id))
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
