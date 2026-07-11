import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    // Bind to all interfaces so the dev server is reachable from outside the devcontainer.
    host: true,
    port: 5173,
  },
})
