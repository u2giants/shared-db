import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { PropertyStatusDialog } from './PropertyStatusDialog'
import type { PropertyRow } from './lib/property-rows'

const property: PropertyRow = {
  id: 'p-avengers', name: 'Avengers', code: 'AVG', status: 'active',
  licensor_name: 'Marvel', licensor_code: 'MRV', character_count: 5,
  source_display: '', plm_display: '', is_orphan: false,
  updated_at: '2026-08-20T12:00:00Z',
}

afterEach(cleanup)

describe('PropertyStatusDialog', () => {
  it('offers only Active and Inactive, defaulting to the current status', () => {
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={vi.fn()} onRefresh={() => undefined} />)
    const select = screen.getByLabelText(/^Status/) as HTMLSelectElement
    expect([...select.options].map(option => option.value)).toEqual(['active', 'inactive'])
    expect(select.value).toBe('active')
  })

  it('requires a reason before the RPC is ever called', () => {
    const onSave = vi.fn()
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={onSave} onRefresh={() => undefined} />)
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    expect(screen.getByRole('alert')).toHaveTextContent('Explain why this status is needed.')
    expect(onSave).not.toHaveBeenCalled()
    // Whitespace is blank too: the RPC refuses btrim('') and so must the dialog.
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: '   ' } })
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    expect(onSave).not.toHaveBeenCalled()
  })

  it('submits the chosen transition with the trimmed reason', async () => {
    const onSave = vi.fn().mockResolvedValue({ success: true, idempotent_replay: false })
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={onSave} onRefresh={() => undefined} />)
    fireEvent.change(screen.getByLabelText(/^Status/), { target: { value: 'inactive' } })
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: '  Licence lapsed  ' } })
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    await screen.findByText('Saved and audited.')
    expect(onSave).toHaveBeenCalledWith('inactive', 'Licence lapsed')
  })

  it('reports an idempotent replay as a success, not a failure', async () => {
    const onSave = vi.fn().mockResolvedValue({ success: true, idempotent_replay: true })
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={onSave} onRefresh={() => undefined} />)
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'Licence lapsed' } })
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    expect(await screen.findByRole('status')).toHaveTextContent('Already saved')
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  it('tells the user to refresh on a stale updated_at instead of retrying', async () => {
    const onSave = vi.fn().mockResolvedValue({ success: false, code: 'stale_token', message: 'someone else changed this Property; reload and try again' })
    const onRefresh = vi.fn()
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={onSave} onRefresh={onRefresh} />)
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'Licence lapsed' } })
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    expect(await screen.findByRole('alert')).toHaveTextContent('changed elsewhere')
    expect(screen.getByRole('button', { name: /refresh table/i })).toBeInTheDocument()
    expect(onSave).toHaveBeenCalledTimes(1)
    fireEvent.click(screen.getByRole('button', { name: /refresh table/i }))
    expect(onRefresh).toHaveBeenCalledTimes(1)
  })

  it('surfaces the RPC’s own error text verbatim', async () => {
    const onSave = vi.fn().mockRejectedValue(new Error('db_data_admin property status: a reason is required'))
    render(<PropertyStatusDialog property={property} onCancel={() => undefined} onSave={onSave} onRefresh={() => undefined} />)
    fireEvent.change(screen.getByLabelText('Reason'), { target: { value: 'Licence lapsed' } })
    fireEvent.click(screen.getByRole('button', { name: /save status/i }))
    expect(await screen.findByRole('alert')).toHaveTextContent('db_data_admin property status: a reason is required')
  })
})
