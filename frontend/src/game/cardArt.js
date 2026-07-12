// 卡面幾何紋（v1.3 A1）：依卡號 seed 的電路走線，同卡號恆同圖。
// 卡號越大走線越多（3 → 2 條、50 → 7 條），42 張各不相同但同一套語言。

const W = 96
const H = 118

/** 確定性 PRNG（同 seed 同序列） */
function mulberry32(seed) {
  return function () {
    seed |= 0
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/**
 * @param {number} number 卡號
 * @returns {{paths: string[], dots: {x: number, y: number}[], w: number, h: number}}
 */
export function cardTraces(number) {
  const rand = mulberry32((number * 2654435761) >>> 0)
  const traceCount = Math.min(7, 2 + Math.floor((number - 3) / 8))
  /** @type {string[]} */
  const paths = []
  /** @type {{x: number, y: number}[]} */
  const dots = []

  for (let t = 0; t < traceCount; t++) {
    let x = 0
    let y = Math.round(8 + rand() * (H - 16))
    let d = `M0 ${y}`
    const segments = 2 + Math.floor(rand() * 3)
    for (let s = 0; s < segments; s++) {
      x = Math.min(W, x + 12 + rand() * 30)
      d += ` H${Math.round(x)}`
      if (x >= W) break
      const ny = Math.max(6, Math.min(H - 6, y + (rand() < 0.5 ? -1 : 1) * Math.round(8 + rand() * 22)))
      if (rand() < 0.5) dots.push({ x: Math.round(x), y })
      d += ` V${ny}`
      y = ny
    }
    if (x < W) d += ` H${W}`
    paths.push(d)
  }
  return { paths, dots, w: W, h: H }
}
