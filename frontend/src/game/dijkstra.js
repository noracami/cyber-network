// 擴建成本預覽——與後端 GridMaster.Engine.Graph 同構的多源 Dijkstra。
// 僅供 UI 即時報價；成交價一律以後端結算為準。

/**
 * 依啟用叢集建立鄰接表。
 * @param {object} map usa_map.json 結構
 * @param {string[]} activeRegions
 * @returns {Map<string, Array<[string, number]>>}
 */
export function buildAdjacency(map, activeRegions) {
  const active = new Set(activeRegions)
  const regionOf = new Map(map.cities.map((c) => [c.id, c.region]))
  const adjacency = new Map()

  for (const { between: [a, b], cost } of map.edges) {
    if (!active.has(regionOf.get(a)) || !active.has(regionOf.get(b))) continue
    if (!adjacency.has(a)) adjacency.set(a, [])
    if (!adjacency.has(b)) adjacency.set(b, [])
    adjacency.get(a).push([b, cost])
    adjacency.get(b).push([a, cost])
  }
  return adjacency
}

/**
 * 玩家網路（sources）到 target 的最低過路費和；無城市回 0；不可達回 null。
 * @param {Map<string, Array<[string, number]>>} adjacency
 * @param {string[]} sources
 * @param {string} target
 */
export function minToll(adjacency, sources, target) {
  if (sources.length === 0) return 0

  /** @type {Map<string, number>} */
  const dist = new Map(sources.map((s) => [s, 0]))
  const done = new Set()
  // 42 節點規模，陣列掃描當 priority queue 就夠了
  const frontier = [...sources]

  while (frontier.length > 0) {
    let best = 0
    for (let i = 1; i < frontier.length; i++) {
      if ((dist.get(frontier[i]) ?? Infinity) < (dist.get(frontier[best]) ?? Infinity)) best = i
    }
    const node = frontier.splice(best, 1)[0]
    if (node === target) return dist.get(node) ?? null
    if (done.has(node)) continue
    done.add(node)

    for (const [neighbor, cost] of adjacency.get(node) || []) {
      const candidate = (dist.get(node) ?? 0) + cost
      if (candidate < (dist.get(neighbor) ?? Infinity)) {
        dist.set(neighbor, candidate)
        frontier.push(neighbor)
      }
    }
  }
  return dist.has(target) ? (dist.get(target) ?? null) : null
}
