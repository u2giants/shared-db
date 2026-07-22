import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { MergeDialog } from './MergeDialog'

const survivor = { id: 's', display_name: 'Keep Me' }
const loser = { id: 'l', display_name: 'Duplicate Me' }
const preview = { success: true, preview_token: 'token', preview: { entity_type: 'customer' as const, survivor, loser, affected_counts: { 'core.company_source_ref.company_id': 2 }, conflicts: [{ key: 'crm.status', app: 'crm', field: 'status', survivor: 'active', loser: 'inactive' }] } }

describe('MergeDialog', () => {
  it('requires conflict resolution, reason, and destructive confirmation', async () => {
    const onPreview = vi.fn().mockResolvedValue(preview)
    const onMerge = vi.fn().mockResolvedValue({ success: true, survivor, audit_id: 'audit' })
    render(<MergeDialog kind="customer" survivor={survivor} candidates={[loser]} onCancel={vi.fn()} onPreview={onPreview} onMerge={onMerge} onMerged={vi.fn()} />)
    fireEvent.change(screen.getByLabelText('Duplicate to absorb'), { target: { value: 'l' } })
    await screen.findByText('Resolve every conflict')
    fireEvent.click(screen.getByRole('button', { name: 'Merge records' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Explain why')
    fireEvent.change(screen.getByPlaceholderText(/permanent audit/i), { target: { value: 'Verified duplicate' } })
    fireEvent.click(screen.getByLabelText(/Keep: active/))
    fireEvent.click(screen.getByLabelText(/I confirm/))
    fireEvent.click(screen.getByRole('button', { name: 'Merge records' }))
    await waitFor(() => expect(onMerge).toHaveBeenCalledWith('l', 'token', 'Verified duplicate', { 'crm.status': 'survivor' }))
  })
})
