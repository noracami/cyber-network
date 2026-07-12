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
  return minTollPath(adjacency, sources, target).cost
}

/**
 * 同 minToll，另回傳最低費路徑的城市序列（含起訖；無路徑時為空陣列）。
 * 供擴建確認時的連線動畫使用。
 * @param {Map<string, Array<[string, number]>>} adjacency
 * @param {string[]} sources
 * @param {string} target
 * @returns {{cost: number | null, path: string[]}}
 */
export function minTollPath(adjacency, sources, target) {
  if (sources.length === 0) return { cost: 0, path: [] }

  /** @type {Map<string, number>} */
  const dist = new Map(sources.map((s) => [s, 0]))
  /** @type {Map<string, string>} */
  const prev = new Map()
  const done = new Set()
  // 42 節點規模，陣列掃描當 priority queue 就夠了
  const frontier = [...sources]

  const pathTo = (node) => {
    const path = [node]
    while (prev.has(path[0])) path.unshift(prev.get(path[0]))
    return path
  }

  while (frontier.length > 0) {
    let best = 0
    for (let i = 1; i < frontier.length; i++) {
      if ((dist.get(frontier[i]) ?? Infinity) < (dist.get(frontier[best]) ?? Infinity)) best = i
    }
    const node = frontier.splice(best, 1)[0]
    if (node === target) return { cost: dist.get(node) ?? null, path: pathTo(node) }
    if (done.has(node)) continue
    done.add(node)

    for (const [neighbor, cost] of adjacency.get(node) || []) {
      const candidate = (dist.get(node) ?? 0) + cost
      if (candidate < (dist.get(neighbor) ?? Infinity)) {
        dist.set(neighbor, candidate)
        prev.set(neighbor, node)
        frontier.push(neighbor)
      }
    }
  }
  return dist.has(target)
    ? { cost: dist.get(target) ?? null, path: pathTo(target) }
    : { cost: null, path: [] }
}
