import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    // Bind to all interfaces so the dev server is reachable from outside the devcontainer.
    host: true,
    port: 5173,
    // 圖鑑頁（#/gallery）直接 import backend/priv/data 的 JSON，放行 repo 根目錄
    fs: { allow: ['..'] },
    proxy: {
      // 開發環境把 /api 與 /auth 轉給 Phoenix；生產環境天然同源（Phoenix 服務 SPA）
      '/api': 'http://localhost:4000',
      '/auth': 'http://localhost:4000',
    },
  },
})
