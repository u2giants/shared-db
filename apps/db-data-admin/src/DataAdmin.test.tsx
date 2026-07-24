import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { FilterHeader } from './DataAdmin'

afterEach(cleanup)

describe('RevoGrid public header filter adapter', () => {
  it('retains focus and caret while publishing controlled filter text', async () => {
    const onFilter = vi.fn()
    function Harness() {
      const [filters, setFilters] = useState<Record<string, string>>({})
      return (
        <FilterHeader
          prop="display_name"
          name="Name"
          filters={filters}
          onFilter={(key, value) => {
            onFilter(key, value)
            setFilters({ [key]: value })
          }}
        />
      )
    }
    render(<Harness />)
    const input = screen.getByRole('textbox', { name: 'Filter Name' }) as HTMLInputElement
    input.focus()
    fireEvent.change(input, { target: { value: 'Acme' } })
    input.setSelectionRange(2, 2)
    expect(onFilter).toHaveBeenCalledWith('display_name', 'Acme')
    expect(input).toHaveFocus()
    expect(input.selectionStart).toBe(2)
  })

  it('exposes the text-filter callback with the same prop signature', () => {
    const onFilter = vi.fn()
    render(<FilterHeader prop="status" name="Status" filters={{}} onFilter={onFilter} />)
    fireEvent.change(screen.getByRole('textbox', { name: 'Filter Status' }), { target: { value: 'act' } })
    expect(onFilter).toHaveBeenCalledWith('status', 'act')
  })

  it('opens a set-filter popover with search, select-all, clear, and checkboxes', () => {
    const onSetFilter = vi.fn()
    const distinctValues = { status: ['', 'active', 'inactive'] }
    render(
      <FilterHeader
        prop="status"
        name="Status"
        filters={{}}
        onFilter={() => undefined}
        setFilters={{}}
        onSetFilter={onSetFilter}
        distinctValues={distinctValues}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Set filter Status' }))
    const dialog = screen.getByRole('dialog', { name: 'Set filter options for Status' })
    expect(within(dialog).getByRole('searchbox', { name: 'Search Status values' })).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Select all' })).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: 'Clear' })).toBeInTheDocument()
    expect(within(dialog).getByText('(Blanks)')).toBeInTheDocument()
    expect(within(dialog).getByText('active')).toBeInTheDocument()

    fireEvent.click(within(dialog).getByRole('button', { name: 'Clear' }))
    expect(onSetFilter).toHaveBeenCalledWith('status', new Set())

    fireEvent.click(within(dialog).getByRole('button', { name: 'Select all' }))
    expect(onSetFilter).toHaveBeenCalledWith('status', null)
  })

  it('filters the checkbox list by the set-filter search box', () => {
    render(
      <FilterHeader
        prop="status"
        name="Status"
        filters={{}}
        distinctValues={{ status: ['alpha', 'bravo', 'charlie'] }}
        setFilters={{}}
        onSetFilter={() => undefined}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Set filter Status' }))
    const dialog = screen.getByRole('dialog', { name: 'Set filter options for Status' })
    fireEvent.change(within(dialog).getByRole('searchbox', { name: 'Search Status values' }), {
      target: { value: 'alp' },
    })
    expect(within(dialog).getByText('alpha')).toBeInTheDocument()
    expect(within(dialog).queryByText('bravo')).not.toBeInTheDocument()
    expect(within(dialog).queryByText('charlie')).not.toBeInTheDocument()
  })

  // Regression guard: the popover must be portalled to document.body, not nested
  // inside .filter-header. When it lived in the header, RevoGrid's header overflow
  // clipped it so only the first checkbox row was visible (found in live testing,
  // invisible to jsdom which has no real layout/clipping).
  it('portals the popover out of the header so the grid cannot clip it', () => {
    const { container } = render(
      <FilterHeader
        prop="status"
        name="Status"
        filters={{}}
        distinctValues={{ status: ['active', 'inactive'] }}
        setFilters={{}}
        onSetFilter={() => undefined}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Set filter Status' }))
    const dialog = screen.getByRole('dialog', { name: 'Set filter options for Status' })
    // Not a descendant of the rendered header subtree…
    expect(container.querySelector('.filter-header')?.contains(dialog)).toBe(false)
    // …and attached under document.body instead.
    expect(document.body.contains(dialog)).toBe(true)
  })

  it('toggles a set-filter value through onSetFilter', () => {
    const onSetFilter = vi.fn()
    render(
      <FilterHeader
        prop="status"
        name="Status"
        filters={{}}
        distinctValues={{ status: ['active', 'inactive'] }}
        setFilters={{ status: new Set(['active', 'inactive']) }}
        onSetFilter={onSetFilter}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Set filter Status' }))
    const dialog = screen.getByRole('dialog', { name: 'Set filter options for Status' })
    const inactive = within(dialog).getByText('inactive').closest('label')!
    fireEvent.click(within(inactive).getByRole('checkbox'))
    expect(onSetFilter).toHaveBeenCalledWith('status', new Set(['active']))
  })
})
