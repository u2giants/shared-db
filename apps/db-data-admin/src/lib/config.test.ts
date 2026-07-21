import { afterEach, describe, expect, it } from 'vitest'
import { readConfig } from './config'

afterEach(() => {
  delete window.__DB_DATA_ADMIN_CONFIG__
})

describe('readConfig', () => {
  it('prefers Coolify-owned runtime configuration', () => {
    window.__DB_DATA_ADMIN_CONFIG__ = {
      supabaseUrl: 'https://preview.example.test',
      supabaseAnonKey: 'public-anon-key',
      authRedirectUrl: 'https://data-dev.designflow.app',
    }

    expect(readConfig()).toEqual(window.__DB_DATA_ADMIN_CONFIG__)
  })

  it('rejects an incomplete runtime configuration', () => {
    window.__DB_DATA_ADMIN_CONFIG__ = { supabaseUrl: 'https://preview.example.test' }
    expect(readConfig()).toBeNull()
  })
})
