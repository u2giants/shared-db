import type { ApiClient } from './data-admin'

// DCP Vault property -> OPA Property review queue.
//
// Background: OPA carries only two creation branches, `disney` (1,445
// Properties) and `lucasfilm` (74). Marvel was merged into the Disney branch
// when Disney moved Marvel submissions off ASGARD, so OPA can never separate
// Marvel from Disney on its own. Owner ruling 2026-08-31 (see
// docs/business-rules/licensing-master-data.md, "OPA cannot separate Marvel
// from Disney") makes the signed contract schedule controlling for that split.
//
// This screen is how a Licensing reviewer records the decision the ruling
// requires, one DCP Vault Property at a time, instead of trading spreadsheets.
// It never invents a placement: the queue only ever offers candidates, and an
// approval is written as a new version of an append-only decision row.

export type MatchCandidate = {
  licensed_property_id: number
  property_name: string
  opa_studio_code: string | null
  /** Pre-selected because the contract title and the OPA name matched exactly. */
  is_selected: boolean
  /** 0-1 name similarity. Null for an exact match. */
  similarity: number | null
}

export type MatchState = 'exact' | 'multiple' | 'suggested' | 'none'

export type PropertyMatchRow = {
  resolution_id: string
  source_system: string
  source_table: string
  source_property_id: string
  display_label: string
  decision_version: number
  approval_status: 'pending' | 'approved' | 'rejected'
  match_state: MatchState
  contract_section: string | null
  contract_clause: number | null
  contract_page: string | null
  contract_title: string | null
  contract_asserted_studio_code: string | null
  candidates: MatchCandidate[]
}

export type MatchQueuePage = { rows: PropertyMatchRow[]; next_cursor: string | null }

export type DecisionResult = {
  success: boolean
  code?: string
  message?: string
  resolution_id?: string
  decision_version?: number
}

/**
 * The review RPCs are added by a governed shared-db migration. Until that lands
 * the tab must say so plainly rather than showing a raw PostgREST error, so the
 * screen can ship ahead of the database change and light up on its own.
 */
export class ReviewQueueUnavailableError extends Error {
  constructor() {
    super('The property match review queue is not enabled on this database yet.')
    this.name = 'ReviewQueueUnavailableError'
  }
}

function isMissingFunction(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const code = 'code' in error ? String(error.code) : ''
  const message = 'message' in error ? String(error.message) : ''
  // PostgREST reports an unknown RPC as PGRST202; PostgreSQL reports 42883.
  return code === 'PGRST202' || code === '42883' || /could not find the function/i.test(message)
}

export function normaliseCandidates(row: PropertyMatchRow): PropertyMatchRow {
  const candidates = [...(row.candidates ?? [])].sort((a, b) => {
    if (a.is_selected !== b.is_selected) return a.is_selected ? -1 : 1
    if ((b.similarity ?? 1) !== (a.similarity ?? 1)) return (b.similarity ?? 1) - (a.similarity ?? 1)
    return a.property_name.localeCompare(b.property_name)
  })
  return { ...row, candidates }
}

/** Human sentence explaining why this row is in the queue. */
export function describeMatchState(row: PropertyMatchRow) {
  switch (row.match_state) {
    case 'multiple':
      return `The contract clause matches ${row.candidates.length} OPA Properties. Choose every one the clause covers.`
    case 'suggested':
      return 'No exact name match. The closest OPA Properties are offered as suggestions only — confirm or reject.'
    case 'none':
      return 'No OPA Property carries this name. Reject it, or select one after checking the contract clause.'
    default:
      return 'The contract clause and the OPA Property name match exactly. Confirm to record the decision.'
  }
}

export function selectedIds(row: PropertyMatchRow) {
  return row.candidates.filter(candidate => candidate.is_selected).map(candidate => candidate.licensed_property_id)
}

export async function loadPropertyMatchQueue(client: ApiClient, search: string | null = null) {
  const rows: PropertyMatchRow[] = []
  let cursor: string | null = null
  do {
    const { data, error } = await client.rpc('db_data_admin_property_match_queue', {
      p_search: search || null,
      p_cursor: cursor,
      p_page_size: 200,
    })
    if (error) {
      if (isMissingFunction(error)) throw new ReviewQueueUnavailableError()
      throw error
    }
    const payload = (data ?? {}) as Partial<MatchQueuePage>
    rows.push(...(payload.rows ?? []).map(normaliseCandidates))
    cursor = payload.next_cursor ?? null
  } while (cursor)
  return rows
}

export async function decidePropertyMatch(
  client: ApiClient,
  input: { resolutionId: string; decision: 'approve' | 'reject'; licensedPropertyIds: number[]; reason: string },
) {
  if (input.decision === 'approve' && input.licensedPropertyIds.length === 0) {
    throw new Error('Select at least one OPA Property before confirming, or reject the row instead.')
  }
  if (!input.reason.trim()) throw new Error('A reason is required so the decision records why.')
  const { data, error } = await client.rpc('db_data_admin_decide_property_match', {
    p_resolution_id: input.resolutionId,
    p_decision: input.decision,
    p_licensed_property_ids: input.decision === 'approve' ? input.licensedPropertyIds : [],
    p_reason: input.reason.trim(),
    p_operation_id: crypto.randomUUID(),
  })
  if (error) {
    if (isMissingFunction(error)) throw new ReviewQueueUnavailableError()
    throw error
  }
  const result = (data ?? {}) as DecisionResult
  if (result.success === false) throw new Error(result.message || 'The decision was not saved.')
  return result
}
