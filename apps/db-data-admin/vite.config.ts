import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

process.env.VITE_BUILD_SHA ??= 'dev'

export default defineConfig({
  plugins: [react()],
  define: {
    __BUILD_SHA__: JSON.stringify(process.env.VITE_BUILD_SHA ?? 'dev'),
  },
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    exclude: ['tests/browser/**', 'node_modules/**', 'dist/**'],
  },
})
