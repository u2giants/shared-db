import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

process.env.VITE_BUILD_SHA ??= 'dev'
process.env.VITE_BUILD_DATE ??= 'dev'

export default defineConfig({
  plugins: [react()],
  define: {
    __BUILD_SHA__: JSON.stringify(process.env.VITE_BUILD_SHA ?? 'dev'),
    __BUILD_DATE__: JSON.stringify(process.env.VITE_BUILD_DATE ?? 'dev'),
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    exclude: ['tests/browser/**', 'node_modules/**', 'dist/**'],
  },
})
