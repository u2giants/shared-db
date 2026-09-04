import { cleanup, fireEvent, render, screen } from '@testing-library/react'

import { afterEach, describe, expect, it, vi } from 'vitest'
import { DataAdmin } from './DataAdmin'
import type { ApiClient } from './lib/data-admin'

afterEach(cleanup)

/**
 * Issue #1322, owner ruling 2026-08-20. The 66 unmatched ColdLion property codes
 * were admitted ONLY on condition that a user can mark a property inactive on our
 * side, because ColdLion has no licence-expiry flag and never will. A status
 * control that exists as a component but is not rendered by any screen does not
 * satisfy that condition, so reachability is the requirement, not a nicety.
 */
function stubClient(): ApiClient {
  return { rpc: vi.fn(async () => ({ data: null, error: null })) } as unknown as ApiClient
}

describe('the property status control is reachable from the app', () => {
  it('offers a Properties tab that renders the property screen', async () => {
    render(<DataAdmin client={stubClient()} email="admin" environmentLabel="Preview database" onSignOut={() => {}} />)
    const tab = await screen.findByRole('button', { name: 'Properties' })
    fireEvent.click(tab)
    expect(tab.className).toContain('active')
    // "Refresh properties" is unique to PropertyTable. An earlier draft asserted on
    // an /inactive/i label and passed even with the tab wired to nothing, because the
    // entity grid has its own "Include inactive" checkbox — so this assertion was
    // checked against the unwired tree and confirmed to go red there.
    expect(await screen.findByRole('button', { name: 'Refresh properties' })).toBeInTheDocument()
  })
})
