import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { PropertyMatchReview } from './PropertyMatchReview'
import type { ApiClient } from './lib/data-admin'
import {
  ReviewQueueUnavailableError,
  decidePropertyMatch,
  defaultSelection,
  describeMatchState,
  loadPropertyMatchQueue,
  matchState,
  normaliseRow,
  type PropertyMatchRow,
} from './lib/property-match'

afterEach(cleanup)

const candidate = (id: number, ordinal: number) => ({ licensed_property_id: id, member_ordinal: ordinal })

const row = (overrides: Partial<PropertyMatchRow> = {}): PropertyMatchRow => ({
  row_key: 'plm.dcp_property|disney_dcpvault|dcpvault:properties/mu/muppets',
  resolution_id: '11111111-1111-4111-8111-111111111111',
  source_system: 'disney_dcpvault',
  source_table: 'plm.dcp_property',
  source_property_id: 'dcpvault:properties/mu/muppets',
  source_property_name: 'Muppets',
  display_label: 'Muppets',
  decision_version: 1,
  approval_status: 'pending',
  evidence_reference: 'dcpvault/properties.json',
  evidence_sha256: 'a'.repeat(64),
  decision_reason: 'proposed by the contract crosswalk',
  contract_asserted_studio_code: 'disney',
  contract_evidence_reference: 'K2557 schedule, disney clause 56, page 23',
  contract_evidence_sha256: 'b'.repeat(64),
  supersedes_resolution_id: null,
  prior_resolution_id: null,
  prior_approval_status: null,
  prior_decision_version: null,
  prior_contract_asserted_studio_code: null,
  candidate_count: 1,
  candidates: [{ ...candidate(333, 1), property_name: 'Muppets' }],
  ...overrides,
})

/** The app client is schema-scoped, so `from` resolves inside the api schema. */
const clientOf = (rpc: ReturnType<typeof vi.fn>, names: { licensed_property_id: number; opa_property_name: string }[] = []) =>
  ({
    rpc,
    from: () => ({ select: () => ({ in: async () => ({ data: names, error: null }) }) }),
  }) as unknown as ApiClient

const queueOnce = (rows: PropertyMatchRow[]) =>
  vi.fn().mockResolvedValueOnce({ data: { rows, next_cursor: null, page_size: 200 }, error: null })

describe('property match queue data', () => {
  it('pages through the queue', async () => {
    let call = 0
    const rpc = vi.fn().mockImplementation(async () => ++call === 1
      ? { data: { rows: [row()], next_cursor: 'Y3Vyc29y', page_size: 1 }, error: null }
      : { data: { rows: [row({ resolution_id: 'r2', display_label: 'Frozen' })], next_cursor: null, page_size: 1 }, error: null })
    const rows = await loadPropertyMatchQueue(clientOf(rpc))
    expect(rows.map(r => r.display_label)).toEqual(['Muppets', 'Frozen'])
  })

  it('names candidates from the OPA reconciliation view', async () => {
    const rpc = queueOnce([row({ candidates: [candidate(333, 1)] as never })])
    const rows = await loadPropertyMatchQueue(clientOf(rpc, [{ licensed_property_id: 333, opa_property_name: 'Muppets' }]))
    expect(rows[0].candidates[0].property_name).toBe('Muppets')
  })

  it('orders candidates by the ordinal the database recorded', () => {
    const sorted = normaliseRow(row({ candidates: [candidate(12, 2), candidate(11, 1)] as never }))
    expect(sorted.candidates.map(c => c.licensed_property_id)).toEqual([11, 12])
  })

  it('reports a missing RPC as an unavailable queue, not a raw error', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } })
    await expect(loadPropertyMatchQueue(clientOf(rpc))).rejects.toBeInstanceOf(ReviewQueueUnavailableError)
  })

  it('pre-ticks a lone candidate but never pre-makes a choice', () => {
    expect(defaultSelection(row())).toEqual([333])
    expect(defaultSelection(row({ candidates: [candidate(11, 1), candidate(12, 2)] as never }))).toEqual([])
  })

  it('explains why each row is in the queue', () => {
    const many = row({ candidates: [candidate(11, 1), candidate(12, 2)] as never })
    expect(matchState(many)).toBe('multiple')
    expect(describeMatchState(many)).toContain('2 OPA Properties')
    expect(describeMatchState(row({ candidates: [] }))).toContain('No OPA Property was proposed')
  })

  it('refuses to approve with nothing selected, or with no reason', async () => {
    const client = clientOf(vi.fn())
    await expect(decidePropertyMatch(client, { resolutionId: 'r1', decision: 'approve', licensedPropertyIds: [], reason: 'ok', clientRequestId: 'c1' }))
      .rejects.toThrow(/Select at least one/)
    await expect(decidePropertyMatch(client, { resolutionId: 'r1', decision: 'approve', licensedPropertyIds: [333], reason: '  ', clientRequestId: 'c1' }))
      .rejects.toThrow(/reason is required/)
  })

  it('sends no members on a rejection, using the names the database expects', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { approval_status: 'rejected' }, error: null })
    await decidePropertyMatch(clientOf(rpc), {
      resolutionId: 'r1', decision: 'reject', licensedPropertyIds: [333], reason: 'Not on K2557', clientRequestId: 'c1',
    })
    expect(rpc.mock.calls[0][1]).toMatchObject({
      p_decision: 'reject', p_licensed_property_ids: [], p_decision_reason: 'Not on K2557', p_client_request_id: 'c1',
    })
  })
})

describe('PropertyMatchReview', () => {
  it('shows the contract evidence beside the property', async () => {
    render(<PropertyMatchReview client={clientOf(queueOnce([row()]))} />)
    expect(await screen.findByRole('heading', { name: 'Muppets' })).toBeInTheDocument()
    expect(screen.getByText(/K2557 schedule, disney clause 56, page 23/)).toBeInTheDocument()
    expect(screen.getByText('disney')).toBeInTheDocument()
  })

  it('blocks confirming until a reason is given, then records the decision', async () => {
    const rpc = queueOnce([row()]).mockResolvedValueOnce({ data: { approval_status: 'approved', decision_version: 2 }, error: null })
    render(<PropertyMatchReview client={clientOf(rpc)} />)
    const confirm = await screen.findByRole('button', { name: /Confirm match/ })
    expect(confirm).toBeDisabled()
    fireEvent.change(screen.getByPlaceholderText(/Why this decision/), { target: { value: 'Contract clause 56' } })
    expect(confirm).toBeEnabled()
    fireEvent.click(confirm)
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('decision recorded'))
    expect(rpc.mock.calls[1][1]).toMatchObject({ p_decision: 'approve', p_licensed_property_ids: [333] })
  })

  it('sends a client request id that is not the resolution id', async () => {
    const rpc = queueOnce([row()]).mockResolvedValueOnce({ data: {}, error: null })
    render(<PropertyMatchReview client={clientOf(rpc)} />)
    await screen.findByRole('heading', { name: 'Muppets' })
    fireEvent.change(screen.getByPlaceholderText(/Why this decision/), { target: { value: 'Clause 56' } })
    fireEvent.click(screen.getByRole('button', { name: /Confirm match/ }))
    await waitFor(() => expect(rpc.mock.calls.length).toBe(2))
    const sent = rpc.mock.calls[1][1] as { p_client_request_id: string; p_resolution_id: string }
    expect(sent.p_client_request_id).toBeTruthy()
    expect(sent.p_client_request_id).not.toBe(sent.p_resolution_id)
  })

  it('lets a reviewer pick both candidates on a two-match clause', async () => {
    const rpc = queueOnce([row({
      display_label: 'Pinocchio',
      candidate_count: 2,
      candidates: [candidate(11, 1), candidate(12, 2)] as never,
    })]).mockResolvedValueOnce({ data: {}, error: null })
    const client = clientOf(rpc, [
      { licensed_property_id: 11, opa_property_name: 'Pinocchio' },
      { licensed_property_id: 12, opa_property_name: 'Pinocchio (Live-Action)' },
    ])
    render(<PropertyMatchReview client={client} />)
    await screen.findByRole('heading', { name: 'Pinocchio' })
    const boxes = screen.getAllByRole('checkbox')
    expect(boxes).toHaveLength(2)
    boxes.forEach(box => fireEvent.click(box))
    fireEvent.change(screen.getByPlaceholderText(/Why this decision/), { target: { value: 'Clause covers both' } })
    fireEvent.click(screen.getByRole('button', { name: /Confirm 2 matches/ }))
    await waitFor(() => expect(rpc.mock.calls[1][1]).toMatchObject({ p_licensed_property_ids: [11, 12] }))
  })

  it('falls back to the OPA id when the name lookup finds nothing', async () => {
    const rpc = queueOnce([row({ candidates: [candidate(999, 1)] as never })])
    render(<PropertyMatchReview client={clientOf(rpc)} />)
    expect(await screen.findByText('OPA Property 999')).toBeInTheDocument()
  })

  it('says the queue is not enabled yet instead of showing a database error', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } })
    render(<PropertyMatchReview client={clientOf(rpc)} />)
    expect(await screen.findByText(/not enabled on this database yet/)).toBeInTheDocument()
  })

  it('scopes an access denial to this screen', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: new Error('licensing manager access required') })
    render(<PropertyMatchReview client={clientOf(rpc)} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Licensing Manager')
  })
})
