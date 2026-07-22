import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { LicensorTree } from './LicensorTree'
import type { ApiClient, LicensorTreeResult } from './lib/data-admin'

afterEach(cleanup)

// The collide property carries mg_code "DC" (Disney's code) but is parented to
// Marvel via its canonical licensor_id — the edge must never come from mg_code.
const fixture: LicensorTreeResult = {
  snapshot: {
    snapshot_at: '2026-07-22T12:00:00Z',
    store: 'core.licensor / core.property (Supabase canonical mirror)',
    source_system: 'designflow_plm',
    feeder_last_sync_at: '2026-07-08T03:30:00Z',
    feeder_last_run_status: 'succeeded',
    feeder_days_stale: 14,
    feeder_available: false,
    live_upstream_reconciliation: false,
    note: 'Snapshot of the canonical Supabase mirror.',
  },
  reconciliation: {
    licensor_count: 2, active_licensor_count: 2,
    property_count: 3, active_property_count: 3,
    properties_with_licensor: 2, orphan_property_count: 1,
    expected_orphan_count_is_zero: false, partition_reconciles: true,
  },
  licensors: [
    {
      id: 'l-marvel', name: 'Marvel', code: 'MRV', status: 'active',
      property_count: 2, updated_at: '2026-07-22T12:00:00Z',
      source_refs: [], plm_context: [{ plm_id: 'm-cw', division_code: 'CW001', mg_code: 'MRV', mg_type: 'licensor', mg_category: 'licensed' }],
      properties: [
        { id: 'p-avengers', name: 'Avengers', code: 'AVG', status: 'active', character_count: 5, source_refs: [{ source_system: 'designflow_plm', source_table: 'merchGroup', source_id: 'x', source_code: 'AVG', source_name: null }], plm_context: [{ plm_id: 'pa', division_code: 'CW001', mg_code: 'AVG', mg_type: 'property', mg_category: 'licensed' }] },
        { id: 'p-spider', name: 'Spider-Man', code: 'SPD', status: 'active', character_count: 0, source_refs: [], plm_context: [{ plm_id: 'ps', division_code: 'CW001', mg_code: 'DC', mg_type: 'property', mg_category: 'licensed' }] },
      ],
    },
    {
      id: 'l-disney', name: 'Disney', code: 'DC', status: 'active',
      property_count: 0, updated_at: '2026-07-22T12:00:00Z',
      source_refs: [], plm_context: [], properties: [],
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

// The two booleans are intentionally decoupled: a recently available feeder
// justifies feeder_available=true but does NOT imply live upstream
// reconciliation, which the RPC reports as false unconditionally.
const feederUpFixture: LicensorTreeResult = {
  ...fixture,
  snapshot: {
    ...fixture.snapshot,
    feeder_last_sync_at: '2026-07-22T10:00:00Z',
    feeder_last_run_status: 'succeeded',
    feeder_days_stale: 0,
    feeder_available: true,
    live_upstream_reconciliation: false,
  },
}

describe('Licensor / Property tree (Step 10)', () => {
  it('renders reconciliation counts, a dated snapshot, and the feeder-down notice', async () => {
    render(<LicensorTree client={makeClient(fixture)} />)
    expect(await screen.findByText(/2 licensors/i)).toBeInTheDocument()
    expect(screen.getByText(/3 properties/i)).toBeInTheDocument()
    expect(screen.getByText('1 orphan', { exact: true })).toBeInTheDocument()
    expect(screen.getByText(/7\/22\/2026/, { exact: false })).toBeInTheDocument()
    expect(screen.getByText(/upstream feeder unavailable/i, { exact: false })).toBeInTheDocument()
  })

  it('surfaces orphan properties loudly and never hides them', async () => {
    render(<LicensorTree client={makeClient(fixture)} />)
    const alert = await screen.findByRole('alert')
    expect(within(alert).getByText('Mystery IP')).toBeInTheDocument()
  })

  it('expands and collapses a licensor to reveal its properties', async () => {
    render(<LicensorTree client={makeClient(fixture)} />)
    expect(await screen.findByText('Marvel')).toBeInTheDocument()
    expect(screen.queryByText('Avengers')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /expand licensor marvel/i }))
    expect(await screen.findByText('Avengers')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /collapse licensor marvel/i }))
    expect(screen.queryByText('Avengers')).not.toBeInTheDocument()
  })

  it('search filters to matching properties and auto-expands the parent', async () => {
    render(<LicensorTree client={makeClient(fixture)} />)
    await screen.findByText('Marvel')
    fireEvent.change(screen.getByPlaceholderText(/search licensors or properties/i), { target: { value: 'Spider' } })
    expect(await screen.findByText('Spider-Man')).toBeInTheDocument()
    expect(screen.queryByText('Avengers')).not.toBeInTheDocument()
    expect(screen.queryByText('Disney')).not.toBeInTheDocument()
  })

  it('parents a property by its canonical licensor even when its mg_code collides', async () => {
    const { container } = render(<LicensorTree client={makeClient(fixture)} />)
    await screen.findByText('Marvel')
    fireEvent.click(screen.getByRole('button', { name: /expand licensor marvel/i }))
    // Spider-Man carries mg_code DC (Disney's code) yet nests under Marvel.
    const marvelItem = container.querySelector('[aria-label="Properties of Marvel"]')
    expect(marvelItem).not.toBeNull()
    expect(within(marvelItem as HTMLElement).getByText('Spider-Man')).toBeInTheDocument()
    // Disney is a separate licensor and exposes no Spider-Man property.
    const disneyItem = container.querySelector('[aria-label="Properties of Disney"]')
    expect(disneyItem).toBeNull()
  })

  it('renders an empty state when search matches nothing', async () => {
    render(<LicensorTree client={makeClient(fixture)} />)
    await screen.findByText('Marvel')
    fireEvent.change(screen.getByPlaceholderText(/search licensors or properties/i), { target: { value: 'zz-nope' } })
    expect(await screen.findByText(/no licensors match/i)).toBeInTheDocument()
  })

  it('keeps live reconciliation unclaimed even when the feeder is recently available', async () => {
    render(<LicensorTree client={makeClient(feederUpFixture)} />)
    // Observed feeder recency is reported as available...
    expect(await screen.findByText(/upstream feeder recently observed/i)).toBeInTheDocument()
    // ...yet live upstream reconciliation is still NOT claimed: the snapshot
    // is mirror-only and never compares against live DesignFlow.
    expect(screen.getByText(/live upstream reconciliation not claimed/i)).toBeInTheDocument()
    expect(screen.queryByText(/live upstream reconciliation claimed/i)).toBeNull()
  })
})
