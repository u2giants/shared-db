import { Save, X } from 'lucide-react'
import { useState } from 'react'
import type { PropertyStatus, PropertyStatusResult } from './lib/data-admin'
import type { PropertyRow } from './lib/property-rows'

type Props = {
  property: PropertyRow
  onCancel: () => void
  onSave: (status: PropertyStatus, reason: string) => Promise<PropertyStatusResult>
  /** Stale-token recovery: reload the table so the next attempt uses a fresh updated_at. */
  onRefresh: () => void
}

// Issue #1322: the owner-ruled counterpart to admitting the unmatched ColdLion
// property codes. ColdLion has no licence-expiry flag, so marking a Property
// inactive on our side is the only thing that stands between a blanket
// admission and resurrecting lapsed licences.
//
// The RPC refuses a blank reason, so a control that cannot collect one would be
// broken by construction: the submit below is stopped before `onSave` fires and
// the reason is trimmed before it leaves the dialog.
export function PropertyStatusDialog({ property, onCancel, onSave, onRefresh }: Props) {
  // Defaults to the current status like RecordEditor's status select: a "set"
  // control must never pre-arm the opposite transition. Saving an unchanged
  // status is answered honestly by the RPC's no_changes code.
  const [status, setStatus] = useState<PropertyStatus>(property.status === 'inactive' ? 'inactive' : 'active')
  const [reason, setReason] = useState('')
  const [state, setState] = useState<'idle' | 'saving' | 'saved' | 'error' | 'conflict'>('idle')
  const [message, setMessage] = useState('')

  const submit = async () => {
    if (!reason.trim()) { setState('error'); setMessage('Explain why this status is needed.'); return }
    setState('saving'); setMessage('Saving…')
    try {
      const result = await onSave(status, reason.trim())
      if (!result.success) {
        // A stale token means someone else changed the row after this grid was
        // loaded. Retrying silently would race them; the user must refresh and
        // retry from the fresh row.
        setState(result.code === 'stale_token' ? 'conflict' : 'error')
        setMessage(result.code === 'stale_token'
          ? 'This Property changed elsewhere. Refresh the table, then try again.'
          : result.message ?? 'The change was not saved.')
        return
      }
      setState('saved')
      // An idempotent replay is a successful no-op replay of an operation that
      // already ran — reported as success, never as a failure.
      setMessage(result.idempotent_replay
        ? 'Already saved — this exact change was recorded earlier.'
        : 'Saved and audited.')
    } catch (cause) {
      // The RPC raises for access denials and blank reasons; surface its own
      // text instead of swallowing it behind a generic message.
      setState('error')
      setMessage(cause instanceof Error ? cause.message : 'The change could not be saved.')
    }
  }

  return <div className="editor-backdrop"><div className="editor" role="dialog" aria-modal="true" aria-labelledby="property-status-title">
    <div className="editor-title"><h2 id="property-status-title">Set Property status</h2><button className="close" aria-label="Close status dialog" onClick={onCancel}><X /></button></div>
    <p className="muted">
      <strong>{property.name}</strong>{property.code ? <> · {property.code}</> : null} · {property.licensor_name} — currently {property.status}.
      Marking it inactive hides it from the default Properties view.
    </p>
    <label>Status<select value={status} onChange={event => setStatus(event.target.value as PropertyStatus)}>
      <option value="active">Active</option>
      <option value="inactive">Inactive</option>
    </select><small>Only Active and Inactive are offered here; the other statuses are not this control's job.</small></label>
    <label>Reason<textarea required value={reason} onChange={event => setReason(event.target.value)} placeholder="Required for the audit history" /></label>
    {message && <div className={`save-state ${state}`} role={state === 'error' || state === 'conflict' ? 'alert' : 'status'}>{message}{state === 'conflict' && <button className="link-button reload-record" type="button" onClick={onRefresh}>Refresh table</button>}</div>}
    <div className="editor-actions"><button className="secondary" onClick={onCancel}>Cancel</button><button className="primary" disabled={state === 'saving' || state === 'saved'} onClick={() => void submit()}><Save /> Save status</button></div>
  </div></div>
}
