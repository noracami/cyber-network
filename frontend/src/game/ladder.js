// 資源價格階梯——與後端 GridMaster.Engine.Ladder 完全同構。
// 「買最便宜、補最貴空格」規則使市場只需數量即可推導所有價格。

const STANDARD = Array.from({ length: 24 }, (_, i) => Math.floor(i / 3) + 1)
const QUANTUM = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16]

/** @param {string} resource */
export function ladder(resource) {
  return resource === 'quantum' ? QUANTUM : STANDARD
}

/**
 * 買 qty 個（從最便宜起）的總價；存量不足回 null。
 * @param {string} resource
 * @param {number} count 市場現量
 * @param {number} qty
 */
export function cost(resource, count, qty) {
  if (qty === 0) return 0
  if (qty > count) return null
  const steps = ladder(resource)
  const start = steps.length - count
  return steps.slice(start, start + qty).reduce((sum, price) => sum + price, 0)
}
