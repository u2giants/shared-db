import { fireEvent, render, screen } from '@testing-library/react'
import { useState } from 'react'
import { describe, expect, it, vi } from 'vitest'
import { FilterHeader } from './DataAdmin'

describe('RevoGrid public header filter adapter', () => {
  it('retains focus and caret while publishing controlled filter text', async () => {
    const onFilter = vi.fn()
    function Harness() { const [filters, setFilters] = useState<Record<string, string>>({}); return <FilterHeader prop="display_name" name="Name" filters={filters} onFilter={(key, value) => { onFilter(key, value); setFilters({ [key]: value }) }} /> }
    render(<Harness />)
    const input = screen.getByRole('textbox', { name: 'Filter Name' }) as HTMLInputElement
    input.focus()
    fireEvent.change(input, { target: { value: 'Acme' } })
    input.setSelectionRange(2, 2)
    expect(onFilter).toHaveBeenCalledWith('display_name', 'Acme')
    expect(input).toHaveFocus()
    expect(input.selectionStart).toBe(2)
  })
})
