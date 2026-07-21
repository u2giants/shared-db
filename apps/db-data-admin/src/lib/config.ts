export interface AppConfig {
  supabaseUrl: string
  supabaseAnonKey: string
  authRedirectUrl: string
}

declare global {
  interface Window {
    __DB_DATA_ADMIN_CONFIG__?: Partial<AppConfig>
  }
}

export function readConfig(): AppConfig | null {
  const runtime = window.__DB_DATA_ADMIN_CONFIG__
  const supabaseUrl = runtime?.supabaseUrl || import.meta.env.VITE_SUPABASE_URL
  const supabaseAnonKey = runtime?.supabaseAnonKey || import.meta.env.VITE_SUPABASE_ANON_KEY
  const authRedirectUrl = runtime?.authRedirectUrl || import.meta.env.VITE_AUTH_REDIRECT_URL

  if (!supabaseUrl || !supabaseAnonKey || !authRedirectUrl) return null

  return { supabaseUrl, supabaseAnonKey, authRedirectUrl }
}
