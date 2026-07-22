import { GitMerge, X } from 'lucide-react'
import { useState } from 'react'
import type { AdminRow, EntityKind, MergePreviewResult, MergeResult } from './lib/data-admin'

type Props = {
  kind: EntityKind; survivor: AdminRow; candidates: AdminRow[]; onCancel: () => void
  onPreview: (loserId: string) => Promise<MergePreviewResult>
  onMerge: (loserId: string, token: string, reason: string, resolutions: Record<string, 'survivor' | 'loser'>) => Promise<MergeResult>
  onMerged: (result: MergeResult, loserId: string) => void
}

const label = (row: AdminRow) => String(row.display_name ?? row.name ?? row.id)
const value = (input: unknown) => input == null ? 'Blank' : typeof input === 'object' ? JSON.stringify(input) : String(input)

export function MergeDialog({ kind, survivor, candidates, onCancel, onPreview, onMerge, onMerged }: Props) {
  const [loserId, setLoserId] = useState('')
  const [preview, setPreview] = useState<MergePreviewResult | null>(null)
  const [resolutions, setResolutions] = useState<Record<string, 'survivor' | 'loser'>>({})
  const [reason, setReason] = useState('')
  const [confirmed, setConfirmed] = useState(false)
  const [state, setState] = useState<'idle' | 'loading' | 'merging' | 'error'>('idle')
  const [message, setMessage] = useState('')

  const choose = async (id: string) => {
    setLoserId(id); setPreview(null); setResolutions({}); setConfirmed(false); setMessage('')
    if (!id) return
    setState('loading')
    try { const result = await onPreview(id); setPreview(result); if (!result.success) setMessage(result.message ?? result.code ?? 'Preview failed.') }
    catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Preview failed.') }
    finally { setState('idle') }
  }
  const submit = async () => {
    const conflicts = preview?.preview?.conflicts ?? []
    if (!reason.trim()) { setMessage('Explain why these records are duplicates.'); setState('error'); return }
    if (conflicts.some(conflict => !resolutions[conflict.key])) { setMessage('Choose a value for every conflict.'); setState('error'); return }
    if (!confirmed || !preview?.preview_token) { setMessage('Confirm that the duplicate will be absorbed.'); setState('error'); return }
    setState('merging'); setMessage('')
    try {
      const result = await onMerge(loserId, preview.preview_token, reason.trim(), resolutions)
      if (!result.success) { setMessage(result.code === 'stale_preview' ? 'The records changed. Generate a new preview before merging.' : result.message ?? result.code ?? 'Merge failed.'); setState('error'); return }
      onMerged(result, loserId)
    } catch (cause) { setMessage(cause instanceof Error ? cause.message : 'Merge failed.'); setState('error') }
  }
  const loser = candidates.find(row => row.id === loserId)
  const counts = Object.entries(preview?.preview?.affected_counts ?? {}).filter(([, count]) => count > 0)
  return <div className="editor-backdrop"><div className="editor merge-dialog" role="dialog" aria-modal="true" aria-labelledby="merge-title">
    <div className="editor-title"><h2 id="merge-title">Merge duplicate {kind === 'customer' ? 'Customer' : 'Vendor'}</h2><button className="close" aria-label="Close merge" onClick={onCancel}><X /></button></div>
    <div className="merge-survivor"><span>Keep this record</span><strong>{label(survivor)}</strong></div>
    <label>Duplicate to absorb<select aria-label="Duplicate to absorb" value={loserId} onChange={event => void choose(event.target.value)}><option value="">Select a duplicate…</option>{candidates.map(row => <option key={row.id} value={row.id}>{label(row)}</option>)}</select></label>
    {state === 'loading' && <p>Building a fresh preview…</p>}
    {preview?.success && loser && <>
      <div className="merge-direction"><strong>{label(loser)}</strong><span>will be absorbed into</span><strong>{label(survivor)}</strong></div>
      <h3>Affected links</h3>{counts.length ? <ul className="merge-counts">{counts.map(([name, count]) => <li key={name}><span>{name}</span><strong>{count}</strong></li>)}</ul> : <p className="muted">No dependent links were found.</p>}
      {(preview.preview?.conflicts ?? []).length > 0 && <><h3>Resolve every conflict</h3><div className="merge-conflicts">{preview.preview!.conflicts.map(conflict => <fieldset key={conflict.key}><legend>{conflict.app.toUpperCase()} · {conflict.field.replaceAll('_', ' ')}</legend><label><input type="radio" name={conflict.key} checked={resolutions[conflict.key] === 'survivor'} onChange={() => setResolutions(current => ({ ...current, [conflict.key]: 'survivor' }))} /> Keep: {value(conflict.survivor)}</label><label><input type="radio" name={conflict.key} checked={resolutions[conflict.key] === 'loser'} onChange={() => setResolutions(current => ({ ...current, [conflict.key]: 'loser' }))} /> Use duplicate: {value(conflict.loser)}</label></fieldset>)}</div></>}
      <label>Reason<textarea value={reason} onChange={event => setReason(event.target.value)} placeholder="Required for the permanent audit history" /></label>
      <label className="check destructive-confirm"><input type="checkbox" checked={confirmed} onChange={event => setConfirmed(event.target.checked)} /> I confirm the duplicate record will be permanently absorbed. This cannot be automatically undone.</label>
    </>}
    {message && <div className="save-state error" role="alert">{message}</div>}
    <div className="editor-actions"><button className="secondary" onClick={onCancel}>Cancel</button><button className="primary destructive" disabled={!preview?.success || state === 'merging'} onClick={() => void submit()}><GitMerge /> {state === 'merging' ? 'Merging…' : 'Merge records'}</button></div>
  </div></div>
}
