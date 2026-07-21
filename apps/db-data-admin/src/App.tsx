import { Database, LogIn, LogOut, ShieldCheck } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { readConfig } from './lib/config'
import { createSupabase } from './lib/supabase'
import './styles.css'

export function App() {
  const config = useMemo(() => readConfig(), [])
  const supabase = useMemo(() => (config ? createSupabase(config) : null), [config])
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(Boolean(supabase))

  useEffect(() => {
    if (!supabase) return
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next))
    return () => data.subscription.unsubscribe()
  }, [supabase])

  const signIn = async () => {
    if (!supabase || !config) return
    await supabase.auth.signInWithOAuth({
      provider: 'azure',
      options: { redirectTo: config.authRedirectUrl, scopes: 'email' },
    })
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand"><Database aria-hidden="true" /><span>DB Data Admin</span></div>
        <span className="build">Build {__BUILD_SHA__}</span>
      </header>
      <section className="hero" aria-labelledby="page-title">
        <div className="eyebrow"><ShieldCheck aria-hidden="true" /> Shared data control room</div>
        <h1 id="page-title">Canonical data, with guardrails.</h1>
        <p>Review Customers, Vendors, Licensors, and Properties shared across POP applications.</p>

        {!config && (
          <div className="notice" role="alert">
            Preview configuration is missing. Copy <code>.env.example</code> to <code>.env.local</code>
            and supply the preview Supabase public values.
          </div>
        )}

        {config && loading && <div className="notice" aria-live="polite">Checking your session…</div>}

        {config && !loading && !session && (
          <button className="primary" type="button" onClick={() => void signIn()}>
            <LogIn aria-hidden="true" /> Sign in with Microsoft
          </button>
        )}

        {config && !loading && session && (
          <div className="signed-in">
            <div>
              <strong>Signed in as {session.user.email}</strong>
              <p>The read contracts are installed in the next preview-first database phase.</p>
            </div>
            <button className="secondary" type="button" onClick={() => void supabase?.auth.signOut()}>
              <LogOut aria-hidden="true" /> Sign out
            </button>
          </div>
        )}
      </section>
    </main>
  )
}
