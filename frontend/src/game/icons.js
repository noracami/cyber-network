// 自製 SVG 圖示集（v1.3 A1）——極簡扁平＋霓虹點綴，24×24 viewBox。
// 每個圖示：專色 + path 清單（stroke 為主、重點處 fill）。
// 由 GameIcon.vue 渲染；文字流（日誌／聊天）仍用 emoji，不經此處。

/**
 * @typedef {{d: string, fill?: boolean, stroke?: boolean, color?: string, w?: number}} IconPath
 * @typedef {{color: string, paths: IconPath[]}} IconDef
 */

/** @type {Record<string, IconDef>} */
export const ICONS = {
  // ── 資源 ──────────────────────────────
  hydro: {
    color: '#4da6ff',
    paths: [
      // 水滴外形
      { d: 'M12 3.2 C 9.6 6.8 6.6 10.6 6.6 14.1 a5.4 5.4 0 0 0 10.8 0 C 17.4 10.6 14.4 6.8 12 3.2 Z', stroke: true },
      // 內部水位線＋節點
      { d: 'M8.8 14.6 H13.4', stroke: true, w: 1.5 },
      { d: 'M15.1 14.6 a1.05 1.05 0 1 0 0.001 0', fill: true },
    ],
  },
  thermal: {
    color: '#fb923c',
    paths: [
      // 火焰外形（面數少的扁平火）
      { d: 'M12 3 C 14.8 6.6 17.6 9.4 17.6 13.6 a5.6 5.6 0 0 1 -11.2 0 C 6.4 9.4 9.2 6.6 12 3 Z', stroke: true },
      // 內焰
      { d: 'M12 10.6 C 13.3 12.3 14.3 13.2 14.3 14.9 a2.3 2.3 0 0 1 -4.6 0 C 9.7 13.2 10.7 12.3 12 10.6 Z', fill: true },
    ],
  },
  waste: {
    color: '#4ade80',
    paths: [
      // 雙迴圈再生箭頭
      { d: 'M18.3 9.6 A7 7 0 0 0 6.9 7.9', stroke: true },
      { d: 'M6.4 4.6 l0.4 3.6 3.6 -0.6', stroke: true, w: 1.6 },
      { d: 'M5.7 14.4 A7 7 0 0 0 17.1 16.1', stroke: true },
      { d: 'M17.6 19.4 l-0.4 -3.6 -3.6 0.6', stroke: true, w: 1.6 },
    ],
  },
  quantum: {
    color: '#e879f9',
    paths: [
      // 原子：核心＋軌道環＋兩顆電子
      { d: 'M12 12 m-2 0 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0', fill: true },
      { d: 'M12 12 m-7 0 a7 7 0 1 0 14 0 a7 7 0 1 0 -14 0', stroke: true, w: 1.5 },
      { d: 'M17 7 a1.3 1.3 0 1 0 0.001 0', fill: true },
      { d: 'M7 17 a1.3 1.3 0 1 0 0.001 0', fill: true },
    ],
  },

  // ── 設施類型（資源以外的三種） ─────────
  hybrid: {
    color: '#4da6ff',
    paths: [
      // 雙色菱晶：左水右火，中央留縫
      { d: 'M11.2 4.6 L4.4 12 L11.2 19.4 Z', fill: true, color: '#4da6ff' },
      { d: 'M12.8 4.6 L19.6 12 L12.8 19.4 Z', fill: true, color: '#fb923c' },
    ],
  },
  self: {
    color: '#a3e635',
    paths: [
      // 葉片外形
      { d: 'M19 5 C 11 5.2 6.3 9.2 5.6 15.6 C 5.5 16.9 5.7 18 6.3 18.8 C 13.5 18.6 18.6 13.4 19 5 Z', stroke: true },
      // 電路葉脈
      { d: 'M7.8 16.8 C 10.5 13.2 13.6 10 16.6 7.4', stroke: true, w: 1.4 },
      { d: 'M10.4 13.4 l-2.2 -0.6 M13.2 10.6 l-0.6 -2.4', stroke: true, w: 1.2 },
    ],
  },
  fusion: {
    color: '#9d6bff',
    paths: [
      // 奇點漩渦：雙臂大弧收進核心，臂端配質點
      { d: 'M12 3.6 A 8.4 8.4 0 0 1 20.4 12 A 8.4 8.4 0 0 1 12 20.4 A 4.6 4.6 0 0 1 7.4 15.8', stroke: true },
      { d: 'M12 20.4 A 8.4 8.4 0 0 1 3.6 12 A 8.4 8.4 0 0 1 12 3.6 A 4.6 4.6 0 0 1 16.6 8.2', stroke: true },
      { d: 'M12 12 m-2 0 a2 2 0 1 0 4 0 a2 2 0 1 0 -4 0', fill: true },
      { d: 'M7.4 15.8 a1.1 1.1 0 1 0 0.001 0', fill: true },
      { d: 'M16.6 8.2 a1.1 1.1 0 1 0 0.001 0', fill: true },
    ],
  },

  // ── 通用 ──────────────────────────────
  bolt: {
    color: '#fbbf24',
    paths: [{ d: 'M13.2 2.5 L5.8 13.4 H10.6 L9.2 21.5 L18.2 9.8 H12.8 Z', fill: true }],
  },
  city: {
    color: '#b8c2e0',
    paths: [
      // 晶片章：切角方框＋內核＋針腳
      { d: 'M8.4 5.5 H15.6 L18.5 8.4 V15.6 L15.6 18.5 H8.4 L5.5 15.6 V8.4 Z', stroke: true },
      { d: 'M10.2 10.2 H13.8 V13.8 H10.2 Z', stroke: true, w: 1.4 },
      { d: 'M10 5.3 V2.8 M14 5.3 V2.8 M10 21.2 V18.7 M14 21.2 V18.7', stroke: true, w: 1.4 },
    ],
  },
  credits: {
    color: '#fbbf24',
    paths: [
      { d: 'M12 2.9 L19.9 7.4 V16.6 L12 21.1 L4.1 16.6 V7.4 Z', stroke: true },
      { d: 'M12.8 6.8 L8.6 12.8 H11.4 L10.6 17.2 L15.6 10.7 H12.4 Z', fill: true },
    ],
  },
}
