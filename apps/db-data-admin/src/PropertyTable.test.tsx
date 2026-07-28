import { cleanup, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { PropertyTable } from './PropertyTable'
import type { ApiClient, LicensorTreeResult } from './lib/data-admin'

afterEach(cleanup)

const fixture: LicensorTreeResult = {
  snapshot: {
    snapshot_at: '2026-07-22T12:00:00Z',
    store: 'core.licensor / core.property (Supabase canonical mirror)',
    source_system: 'designflow_plm',
    feeder_last_sync_at: '2026-07-22T10:00:00Z',
    feeder_last_run_status: 'succeeded',
    feeder_days_stale: 0,
    feeder_available: true,
    live_upstream_reconciliation: false,
    note: 'Snapshot of the canonical Supabase mirror.',
  },
  reconciliation: {
    licensor_count: 1, active_licensor_count: 1,
    property_count: 2, active_property_count: 2,
    properties_with_licensor: 1, orphan_property_count: 1,
    expected_orphan_count_is_zero: false, partition_reconciles: true,
  },
  licensors: [
    {
      id: 'l-marvel', name: 'Marvel', code: 'MRV', status: 'active',
      property_count: 1, source_refs: [], plm_context: [],
      properties: [
        { id: 'p-avengers', name: 'Avengers', code: 'AVG', status: 'active', character_count: 5, source_refs: [], plm_context: [] },
      ],
    },
  ],
  orphan_properties: [
    { id: 'o-1', name: 'Mystery IP', code: 'MYS', status: 'active', licensor_id: null, character_count: 0, source_refs: [], plm_context: [] },
  ],
  next_cursor: null, page_size: 200,
}

function makeClient(payload: LicensorTreeResult): ApiClient {
  return { rpc: vi.fn(async () => ({ data: payload, error: null })) } as unknown as ApiClient
}

function makeFailingClient(message: string): ApiClient {
  return { rpc: vi.fn(async () => ({ data: null, error: new Error(message) })) } as unknown as ApiClient
}

describe('PropertyTable', () => {
  it('reads the existing tree contract rather than a separate property RPC', async () => {
    const client = makeClient(fixture)
    render(<PropertyTable client={client} />)
    await waitFor(() => expect(client.rpc).toHaveBeenCalled())
    expect(vi.mocked(client.rpc).mock.calls[0][0]).toBe('db_data_admin_licensor_property_tree')
  })

  it('counts every property, orphans included', async () => {
    render(<PropertyTable client={makeClient(fixture)} />)
    expect(await screen.findByText('2 of 2 properties')).toBeInTheDocument()
  })

  it('warns loudly when a property has no licensor', async () => {
    render(<PropertyTable client={makeClient(fixture)} />)
    expect(await screen.findByRole('status')).toHaveTextContent('1 property has no licensor')
  })

  it('stays silent about orphans when there are none', async () => {
    render(<PropertyTable client={makeClient({ ...fixture, orphan_properties: [] })} />)
    expect(await screen.findByText('1 of 1 properties')).toBeInTheDocument()
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('shows the access-denied panel instead of an empty table', async () => {
    render(<PropertyTable client={makeFailingClient('permission denied for function')} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Access denied')
  })

  it('surfaces other load failures as an inline error', async () => {
    render(<PropertyTable client={makeFailingClient('connection reset')} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('connection reset')
  })
})
