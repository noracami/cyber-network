// 確定性 PRNG（mulberry32）：同 seed 同序列。
// 卡面幾何紋、地圖背景紋理共用——「隨機但每次都一樣」是視覺穩定的前提。

/** @param {number} seed */
export function mulberry32(seed) {
  return function () {
    seed |= 0
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
