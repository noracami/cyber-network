import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    // Bind to all interfaces so the dev server is reachable from outside the devcontainer.
    host: true,
    port: 5173,
    proxy: {
      // 開發環境把 /api 轉給 Phoenix，生產環境由 Caddy 處理同源轉發
      '/api': 'http://localhost:4000',
    },
  },
})
