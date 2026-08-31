import { Check, RefreshCw, Search, X } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { ApiClient } from './lib/data-admin'
import {
  ReviewQueueUnavailableError,
  decidePropertyMatch,
  describeMatchState,
  loadPropertyMatchQueue,
  selectedIds,
  type PropertyMatchRow,
} from './lib/property-match'

type Props = { client: ApiClient }

const stateLabel: Record<PropertyMatchRow['match_state'], string> = {
  exact: 'Exact name match',
  multiple: 'More than one candidate',
  suggested: 'Suggestion only',
  none: 'No candidate',
}

export function PropertyMatchReview({ client }: Props) {
  const [rows, setRows] = useState<PropertyMatchRow[]>([])
  const [chosen, setChosen] = useState<Record<string, number[]>>({})
  const [reasons, setReasons] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [denied, setDenied] = useState(false)
  const [unavailable, setUnavailable] = useState(false)
  const [search, setSearch] = useState('')
  const [saved, setSaved] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true); setError(null); setDenied(false); setUnavailable(false)
    try {
      const loaded = await loadPropertyMatchQueue(client)
      setRows(loaded)
      setChosen(Object.fromEntries(loaded.map(row => [row.resolution_id, selectedIds(row)])))
    } catch (cause) {
      if (cause instanceof ReviewQueueUnavailableError) setUnavailable(true)
      else {
        const message = cause instanceof Error ? cause.message : ''
        if (/permission|licensing|access/i.test(message)) setDenied(true)
        else setError(message || 'The review queue could not be loaded.')
      }
    } finally { setLoading(false) }
  }, [client])

  // Same pattern as the other mounted review screens: the request owns the
  // loading state from the moment the view mounts.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load() }, [load])

  const visible = useMemo(() => {
    const term = search.trim().toLowerCase()
    if (!term) return rows
    return rows.filter(row => `${row.display_label} ${row.contract_title ?? ''} ${row.candidates.map(c => c.property_name).join(' ')}`.toLowerCase().includes(term))
  }, [rows, search])

  const toggle = (resolutionId: string, licensedPropertyId: number) => setChosen(current => {
    const picked = current[resolutionId] ?? []
    return {
      ...current,
      [resolutionId]: picked.includes(licensedPropertyId)
        ? picked.filter(id => id !== licensedPropertyId)
        : [...picked, licensedPropertyId],
    }
  })

  const decide = async (row: PropertyMatchRow, decision: 'approve' | 'reject') => {
    setBusy(row.resolution_id); setError(null); setSaved(null)
    try {
      await decidePropertyMatch(client, {
        resolutionId: row.resolution_id,
        decision,
        licensedPropertyIds: chosen[row.resolution_id] ?? [],
        reason: reasons[row.resolution_id] ?? '',
      })
      setRows(current => current.filter(candidate => candidate.resolution_id !== row.resolution_id))
      setSaved(`${row.display_label} — ${decision === 'approve' ? 'decision recorded' : 'rejected'}.`)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The decision was not saved.')
    } finally { setBusy(null) }
  }

  if (denied) return <section className="access-denied" role="alert">
    <h1>Access denied</h1>
    <p>Recording a Property match requires an active Licensing Manager grant.</p>
  </section>

  if (unavailable) return <section className="workspace property-match" aria-live="polite">
    <h1>Property matches</h1>
    <p className="muted">
      This review queue is not enabled on this database yet. The screen is in place and will
      populate as soon as the governed database change that creates the queue is applied.
    </p>
  </section>

  return <section className="workspace property-match">
    <div className="controls">
      <label className="search">
        <Search aria-hidden="true" />
        <span className="sr-only">Search property matches</span>
        <input placeholder="Search property matches" value={search} onChange={event => setSearch(event.target.value)} />
      </label>
      <button className="icon-button" aria-label="Refresh property matches" onClick={() => void load()}><RefreshCw /></button>
    </div>
    <p className="muted">
      Each row is one DCP Vault Property waiting on a decision about which OPA Property it is.
      OPA cannot tell Marvel from Disney on its own, so the signed contract clause shown beside
      each row is the controlling evidence. Nothing here is placed automatically.
    </p>
    {error && <div className="inline-error" role="alert">{error}</div>}
    {saved && <p className="muted" role="status">{saved}</p>}
    <div aria-busy={loading}>
      {visible.map(row => {
        const picked = chosen[row.resolution_id] ?? []
        return <article key={row.resolution_id} className="match-row" aria-labelledby={`match-${row.resolution_id}`}>
          <header>
            <h2 id={`match-${row.resolution_id}`}>{row.display_label}</h2>
            <span className={`match-state match-state-${row.match_state}`}>{stateLabel[row.match_state]}</span>
          </header>
          <p className="muted">{describeMatchState(row)}</p>
          {row.contract_title && <p className="muted contract-evidence">
            Contract: <strong>{row.contract_title}</strong>
            {row.contract_section && <> — {row.contract_section} section</>}
            {row.contract_clause !== null && <>, clause {row.contract_clause}</>}
            {row.contract_page && <>, page {row.contract_page}</>}
          </p>}
          {row.candidates.length === 0
            ? <p className="muted">No OPA Property carries this name.</p>
            : <ul className="match-candidates">
              {row.candidates.map(candidate => <li key={candidate.licensed_property_id}>
                <label>
                  <input
                    type="checkbox"
                    checked={picked.includes(candidate.licensed_property_id)}
                    onChange={() => toggle(row.resolution_id, candidate.licensed_property_id)}
                  />
                  <span>{candidate.property_name}</span>
                  <span className="muted"> · OPA {candidate.licensed_property_id}</span>
                  {candidate.opa_studio_code && <span className="muted"> · {candidate.opa_studio_code} branch</span>}
                  {candidate.similarity !== null && <span className="muted"> · {Math.round(candidate.similarity * 100)}% name match</span>}
                </label>
              </li>)}
            </ul>}
          <label className="match-reason">
            <span>Reason</span>
            <input
              placeholder="Why this decision (recorded with your name)"
              value={reasons[row.resolution_id] ?? ''}
              onChange={event => setReasons(current => ({ ...current, [row.resolution_id]: event.target.value }))}
            />
          </label>
          <div className="match-actions">
            <button
              disabled={busy === row.resolution_id || picked.length === 0 || !(reasons[row.resolution_id] ?? '').trim()}
              onClick={() => void decide(row, 'approve')}
            ><Check aria-hidden="true" /> Confirm {picked.length > 1 ? `${picked.length} matches` : 'match'}</button>
            <button
              className="secondary"
              disabled={busy === row.resolution_id || !(reasons[row.resolution_id] ?? '').trim()}
              onClick={() => void decide(row, 'reject')}
            ><X aria-hidden="true" /> Not on this contract</button>
          </div>
        </article>
      })}
      {loading && <div className="grid-loading">Loading…</div>}
      {!loading && visible.length === 0 && <p className="muted">Nothing is waiting for a decision.</p>}
    </div>
    <footer className="grid-footer"><span>{visible.length} of {rows.length} awaiting a decision</span></footer>
  </section>
}
