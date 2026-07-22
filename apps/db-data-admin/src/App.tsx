import { Database, LogIn, ShieldCheck } from 'lucide-react'
import { useEffect, useMemo, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { readConfig } from './lib/config'
import { formatBuildLabel, readOAuthCallbackError } from './lib/presentation'
import { createSupabase } from './lib/supabase'
import { DataAdmin } from './DataAdmin'
import './styles.css'

export function App() {
  const config = useMemo(() => readConfig(), [])
  const supabase = useMemo(() => (config ? createSupabase(config) : null), [config])
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(Boolean(supabase))
  const [authError, setAuthError] = useState(() => readOAuthCallbackError(window.location))
  const buildLabel = formatBuildLabel(__BUILD_SHA__, __BUILD_DATE__)

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
    setAuthError(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'azure',
      options: { redirectTo: config.authRedirectUrl, scopes: 'email' },
    })
    if (error) {
      setAuthError({ code: 'sign_in_failed', description: error.message })
    }
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand"><Database aria-hidden="true" /><span>DB Data Admin</span></div>
        <span className="build" title={`Full commit ${__BUILD_SHA__}`}>Build {buildLabel}</span>
      </header>
      <section className={session ? 'admin-surface' : 'hero'} aria-labelledby="page-title">
        {!session && <><div className="eyebrow"><ShieldCheck aria-hidden="true" /> Shared data control room</div>
        <h1 id="page-title">Canonical data, with guardrails.</h1>
        <p>Review Customers and Vendors shared across POP applications.</p></>}

        {!config && (
          <div className="notice" role="alert">
            Preview configuration is missing. Copy <code>.env.example</code> to <code>.env.local</code>
            and supply the preview Supabase public values.
          </div>
        )}

        {config && loading && <div className="notice" aria-live="polite">Checking your session…</div>}

        {config && authError && (
          <div className="notice error-notice" role="alert">
            <strong>Microsoft sign-in could not be completed.</strong>
            <p>{authError.description}</p>
            <small>Error code: {authError.code}</small>
          </div>
        )}

        {config && !loading && !session && (
          <button className="primary" type="button" onClick={() => void signIn()}>
            <LogIn aria-hidden="true" /> Sign in with Microsoft
          </button>
        )}

        {config && !loading && session && supabase && <DataAdmin client={supabase} email={session.user.email} onSignOut={() => void supabase.auth.signOut()} />}
      </section>
    </main>
  )
}
