import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { PropertyMatchReview } from './PropertyMatchReview'
import type { ApiClient } from './lib/data-admin'
import {
  ReviewQueueUnavailableError,
  decidePropertyMatch,
  describeMatchState,
  loadPropertyMatchQueue,
  normaliseCandidates,
  type PropertyMatchRow,
} from './lib/property-match'

afterEach(cleanup)

const candidate = (id: number, name: string, selected = false, similarity: number | null = null) =>
  ({ licensed_property_id: id, property_name: name, opa_studio_code: 'disney', is_selected: selected, similarity })

const row = (overrides: Partial<PropertyMatchRow> = {}): PropertyMatchRow => ({
  resolution_id: 'r1',
  source_system: 'disney_dcpvault',
  source_table: 'plm.dcp_property',
  source_property_id: 'dcpvault:properties/mu/muppets',
  display_label: 'Muppets',
  decision_version: 1,
  approval_status: 'pending',
  match_state: 'exact',
  contract_section: 'disney',
  contract_clause: 56,
  contract_page: '23',
  contract_title: 'MUPPETS',
  contract_asserted_studio_code: 'disney',
  candidates: [candidate(333, 'Muppets', true)],
  ...overrides,
})

const clientReturning = (data: unknown, rpc = vi.fn()) => {
  rpc.mockResolvedValue({ data, error: null })
  return { rpc } as unknown as ApiClient
}

describe('property match queue data', () => {
  it('pages through the queue and sorts pre-selected candidates first', async () => {
    let call = 0
    const client = { rpc: async () => ++call === 1
      ? { data: { rows: [row()], next_cursor: 'next' }, error: null }
      : { data: { rows: [row({ resolution_id: 'r2', display_label: 'Frozen' })], next_cursor: null }, error: null },
    } as unknown as ApiClient
    const rows = await loadPropertyMatchQueue(client)
    expect(rows.map(r => r.display_label)).toEqual(['Muppets', 'Frozen'])
  })

  it('orders candidates by selection then similarity', () => {
    const sorted = normaliseCandidates(row({
      candidates: [candidate(2, 'Pinocchio (Live-Action)', false, 0.8), candidate(3, 'Pinocchio Other', false, 0.9), candidate(1, 'Pinocchio', true)],
    }))
    expect(sorted.candidates.map(c => c.licensed_property_id)).toEqual([1, 3, 2])
  })

  it('reports a missing RPC as an unavailable queue, not a raw error', async () => {
    const client = { rpc: async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }) } as unknown as ApiClient
    await expect(loadPropertyMatchQueue(client)).rejects.toBeInstanceOf(ReviewQueueUnavailableError)
  })

  it('explains why each row is in the queue', () => {
    expect(describeMatchState(row({ match_state: 'multiple', candidates: [candidate(1, 'A'), candidate(2, 'B')] }))).toContain('2 OPA Properties')
    expect(describeMatchState(row({ match_state: 'suggested' }))).toContain('suggestions only')
    expect(describeMatchState(row({ match_state: 'none' }))).toContain('No OPA Property carries this name')
  })

  it('refuses to approve with nothing selected, or with no reason', async () => {
    const client = clientReturning({ success: true })
    await expect(decidePropertyMatch(client, { resolutionId: 'r1', decision: 'approve', licensedPropertyIds: [], reason: 'ok' }))
      .rejects.toThrow(/Select at least one/)
    await expect(decidePropertyMatch(client, { resolutionId: 'r1', decision: 'approve', licensedPropertyIds: [333], reason: '  ' }))
      .rejects.toThrow(/reason is required/)
  })

  it('sends no members on a rejection', async () => {
    const rpc = vi.fn()
    const client = clientReturning({ success: true, decision_version: 2 }, rpc)
    await decidePropertyMatch(client, { resolutionId: 'r1', decision: 'reject', licensedPropertyIds: [333], reason: 'Not on K2557' })
    expect(rpc.mock.calls[0][1]).toMatchObject({ p_decision: 'reject', p_licensed_property_ids: [], p_reason: 'Not on K2557' })
  })
})

describe('PropertyMatchReview', () => {
  it('shows the contract evidence beside the property', async () => {
    const client = clientReturning({ rows: [row()], next_cursor: null })
    render(<PropertyMatchReview client={client} />)
    expect(await screen.findByRole('heading', { name: 'Muppets' })).toBeInTheDocument()
    expect(screen.getByText(/disney section/)).toBeInTheDocument()
    expect(screen.getByText(/clause 56/)).toBeInTheDocument()
    expect(screen.getByText(/page 23/)).toBeInTheDocument()
  })

  it('blocks confirming until a reason is given, then records the decision', async () => {
    const rpc = vi.fn()
      .mockResolvedValueOnce({ data: { rows: [row()], next_cursor: null }, error: null })
      .mockResolvedValueOnce({ data: { success: true, decision_version: 2 }, error: null })
    const client = { rpc } as unknown as ApiClient
    render(<PropertyMatchReview client={client} />)
    const confirm = await screen.findByRole('button', { name: /Confirm match/ })
    expect(confirm).toBeDisabled()
    fireEvent.change(screen.getByPlaceholderText(/Why this decision/), { target: { value: 'Contract clause 56' } })
    expect(confirm).toBeEnabled()
    fireEvent.click(confirm)
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('decision recorded'))
    expect(rpc.mock.calls[1][1]).toMatchObject({ p_decision: 'approve', p_licensed_property_ids: [333] })
  })

  it('lets a reviewer pick both candidates on a two-match clause', async () => {
    const rpc = vi.fn()
      .mockResolvedValueOnce({ data: { rows: [row({
        display_label: 'Pinocchio', match_state: 'multiple',
        candidates: [candidate(11, 'Pinocchio', true), candidate(12, 'Pinocchio (Live-Action)')],
      })], next_cursor: null }, error: null })
      .mockResolvedValueOnce({ data: { success: true }, error: null })
    const client = { rpc } as unknown as ApiClient
    render(<PropertyMatchReview client={client} />)
    await screen.findByRole('heading', { name: 'Pinocchio' })
    fireEvent.click(screen.getByRole('checkbox', { name: /Live-Action/ }))
    fireEvent.change(screen.getByPlaceholderText(/Why this decision/), { target: { value: 'Clause covers both' } })
    fireEvent.click(screen.getByRole('button', { name: /Confirm 2 matches/ }))
    await waitFor(() => expect(rpc.mock.calls[1][1]).toMatchObject({ p_licensed_property_ids: [11, 12] }))
  })

  it('says the queue is not enabled yet instead of showing a database error', async () => {
    const client = { rpc: async () => ({ data: null, error: { code: 'PGRST202', message: 'Could not find the function' } }) } as unknown as ApiClient
    render(<PropertyMatchReview client={client} />)
    expect(await screen.findByText(/not enabled on this database yet/)).toBeInTheDocument()
  })

  it('scopes an access denial to this screen', async () => {
    const client = { rpc: async () => ({ data: null, error: new Error('licensing manager access required') }) } as unknown as ApiClient
    render(<PropertyMatchReview client={client} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Licensing Manager')
  })
})
