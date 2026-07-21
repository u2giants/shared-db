export interface AppConfig {
  supabaseUrl: string
  supabaseAnonKey: string
  authRedirectUrl: string
}

export function readConfig(): AppConfig | null {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
  const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY
  const authRedirectUrl = import.meta.env.VITE_AUTH_REDIRECT_URL

  if (!supabaseUrl || !supabaseAnonKey || !authRedirectUrl) return null

  return { supabaseUrl, supabaseAnonKey, authRedirectUrl }
}
