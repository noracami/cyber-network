// 資源容量與供電可行性——後端 GridMaster.Engine.Capacity 的 JS 鏡像。
// 僅供 UI 預先擋非法操作；最終驗證在後端。

const RESOURCE_TYPES = ['hydro', 'thermal', 'waste', 'quantum']

/** 各類型儲存容量（燃料需求 ×2；hybrid 彈性容量）。 */
export function capsOf(plants) {
  const caps = { hydro: 0, thermal: 0, waste: 0, quantum: 0, hybrid: 0 }
  for (const plant of plants) {
    const cap = 2 * plant.fuel
    if (plant.type === 'hybrid') caps.hybrid += cap
    else if (RESOURCE_TYPES.includes(plant.type)) caps[plant.type] += cap
  }
  return caps
}

/** 持有量 resources 是否裝得進容量。 */
export function fits(caps, resources) {
  return (
    resources.waste <= caps.waste &&
    resources.quantum <= caps.quantum &&
    resources.hydro <= caps.hydro + caps.hybrid &&
    resources.thermal <= caps.thermal + caps.hybrid &&
    resources.hydro + resources.thermal <= caps.hydro + caps.thermal + caps.hybrid
  )
}

/** 啟動 plants 所需資源是否足夠（hybrid 可吃水力或火力）。 */
export function burnFeasible(resources, plants) {
  const need = { hydro: 0, thermal: 0, waste: 0, quantum: 0, hybrid: 0 }
  for (const plant of plants) {
    if (plant.type === 'hybrid') need.hybrid += plant.fuel
    else if (RESOURCE_TYPES.includes(plant.type)) need[plant.type] += plant.fuel
  }
  const leftoverHydro = resources.hydro - need.hydro
  const leftoverThermal = resources.thermal - need.thermal
  return (
    resources.waste >= need.waste &&
    resources.quantum >= need.quantum &&
    leftoverHydro >= 0 &&
    leftoverThermal >= 0 &&
    leftoverHydro + leftoverThermal >= need.hybrid
  )
}
