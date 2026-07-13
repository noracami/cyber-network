<script setup>
// 卡面圖鑑（#/gallery）：離線展示頁,數據直接 import 專案 JSON,不經後端。
// 插圖約定:public/cards/plant_NN.png,缺圖時顯示類型 icon 佔位。
import deck from '../../../backend/priv/data/cyber_decks.json'
import { TYPE_META } from '../game/text'
import GameIcon from './GameIcon.vue'

const plants = deck.plants

/** 風格比稿:同題材(#3 老舊火力機櫃)六種風格,皆已過四色量化 */
const styles = [
  { file: 'constructivist', label: '構成主義海報' },
  { file: 'linocut', label: '麻膠版畫' },
  { file: 'risograph', label: 'Risograph 孔版' },
  { file: 'matchbox', label: '昭和火柴盒' },
  { file: 'midcentury', label: '世紀中現代' },
  { file: 'pixel', label: '像素藝術' },
]

/** @param {number} number */
function artUrl(number) {
  return `/cards/plant_${String(number).padStart(2, '0')}.png`
}

/** 缺圖時藏掉 img,露出底下的佔位 icon */
function hideImg(event) {
  event.target.style.display = 'none'
}

/** 類型色帶;混合廠用水火漸層(同 PlantCard) */
function band(plant) {
  if (plant.type === 'hybrid') return 'linear-gradient(90deg, #4da6ff, #fb923c)'
  return TYPE_META[plant.type]?.color || 'var(--border)'
}
</script>

<template>
  <div class="gallery">
    <header class="gallery-head">
      <h1>卡面圖鑑 <span class="gallery-count">{{ plants.length }} 張</span></h1>
      <router-link class="btn ghost" to="/">← 回遊戲</router-link>
    </header>
    <section class="style-section">
      <h2>風格比稿 <span class="gallery-count">#3 老舊火力機櫃 × 6 風格(四色量化後)</span></h2>
      <div class="style-grid">
        <div v-for="style in styles" :key="style.file" class="gcard">
          <div class="gcard-art style-art">
            <img :src="`/cards/styles/${style.file}.png`" alt="" loading="lazy" />
          </div>
          <div class="gcard-body">
            <div class="gcard-name style-label">{{ style.label }}</div>
          </div>
        </div>
      </div>
    </section>

    <h2 class="deck-title">全卡表</h2>
    <div class="gallery-grid">
      <div v-for="plant in plants" :key="plant.number" class="gcard">
        <div class="gcard-band" :style="{ background: band(plant) }"></div>
        <div class="gcard-art">
          <div class="gcard-placeholder">
            <GameIcon :name="plant.type" :size="42" />
          </div>
          <img :src="artUrl(plant.number)" alt="" loading="lazy" @error="hideImg" />
        </div>
        <div class="gcard-body">
          <div class="gcard-head">
            <span class="gcard-number">{{ plant.number }}</span>
            <span class="gcard-type" :style="{ color: TYPE_META[plant.type]?.color }">
              {{ TYPE_META[plant.type]?.label }}
            </span>
          </div>
          <div class="gcard-name">{{ plant.name }}</div>
          <div class="gcard-stats">
            <template v-if="plant.fuel > 0">
              <GameIcon :name="plant.type" :size="12" /><span>×{{ plant.fuel }}</span>
            </template>
            <span v-else>免燃料</span>
            <span class="gcard-arrow">→</span>
            <GameIcon name="bolt" :size="12" /><span>{{ plant.powers }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.gallery {
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  padding: 16px;
}

.gallery-head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 16px;
}

.gallery-head h1 {
  font-size: 1.2rem;
  color: var(--text-bright);
}

.gallery-count {
  font-size: 0.8rem;
  color: var(--text-dim);
  margin-left: 8px;
}

.gallery-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 14px;
}

.style-section h2,
.deck-title {
  font-size: 0.95rem;
  color: var(--text-bright);
  margin: 0 0 10px;
}

.deck-title {
  margin-top: 24px;
}

.style-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
  gap: 14px;
}

.style-art img {
  object-fit: contain;
}

.style-label {
  min-height: 0;
  text-align: center;
  color: var(--text);
}

.gcard {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--bg-raised);
}

.gcard-band {
  height: 3px;
}

.gcard-art {
  position: relative;
  aspect-ratio: 2 / 3;
  background: #f2e8d5;
}

.gcard-art img {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.gcard-placeholder {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0.3;
}

.gcard-body {
  padding: 8px 10px 10px;
}

.gcard-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.gcard-number {
  font-family: var(--mono);
  font-size: 1.2rem;
  font-weight: 700;
  color: var(--text-bright);
}

.gcard-type {
  font-size: 0.7rem;
}

.gcard-name {
  font-size: 0.75rem;
  color: var(--text-dim);
  line-height: 1.3;
  min-height: 2em;
  margin: 2px 0 4px;
}

.gcard-stats {
  display: flex;
  align-items: center;
  gap: 3px;
  font-size: 0.75rem;
  color: var(--text);
}

.gcard-arrow {
  color: var(--text-dim);
}
</style>
