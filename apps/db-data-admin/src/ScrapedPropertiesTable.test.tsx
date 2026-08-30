import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ScrapedPropertiesTable } from './ScrapedPropertiesTable'
import { groupScrapedProperties, presentScrapedProperty, type ApiClient, type ScrapedPropertyRow } from './lib/data-admin'
import { scrapedPropertiesColumns } from './scraped-properties-columns'

const row = (key: string, licensor: string, source = 'disney_dcp'): ScrapedPropertyRow => ({
  id: key, row_key: key, presentation_licensor_key: licensor.toLowerCase().replaceAll(' ', '-'), presentation_licensor_name: licensor,
  source_system: source, source_table: 'plm.source_property', source_property_id: key,
  source_property_name: `${licensor} property`, display_label: `${licensor} property`, source_status: null,
  provenance_kind: 'metadata_properties_array', latest_seen_at: null, capture_marker: null,
  source_purpose: 'Creative', review_reason: 'Current approved evidence supports this presentation.',
  evidence_basis: 'synthetic contract fixture', review_guidance: 'No action required.',
})

describe('ScrapedPropertiesTable', () => {
  it('puts authoritative mapping and contract status beside Property', () => {
    expect(scrapedPropertiesColumns.slice(0, 4).map(column => column.name)).toEqual([
      'Property',
      'Authoritative Submissions',
      'Mapping',
      'Contract status',
    ])
  })

  it('presents an authoritative one-to-many mapping and sanitized contract status', () => {
    const presented = presentScrapedProperty({
      ...row('mapped', 'Example'),
      mapping_state: 'mapped',
      submissions: [
        { source_system: 'submissions', source_table: 'source.properties', source_id: 'a', display_label: 'Submission A' },
        { source_system: 'submissions', source_table: 'source.properties', source_id: 'b', display_label: 'Submission B' },
      ],
      contract_status: 'evidenced',
    })
    expect(presented.submission_display).toBe('Submission A • Submission B')
    expect(presented.contract_status_display).toBe('Entitled — evidence on file')
    expect(presented.is_unmapped_creative).toBe(false)
  })

  it('keeps an unmapped Creative row visible and marks every grid cell red', () => {
    const presented = presentScrapedProperty(row('unmapped', 'Example'))
    expect(presented.submission_display).toBe('Unmapped')
    expect(presented.is_unmapped_creative).toBe(true)
    expect(scrapedPropertiesColumns.every(column => column.cellProperties?.({ model: presented } as never)?.className === 'unmapped-creative-cell')).toBe(true)
  })

  it('does not mark a Submissions source row as unmapped Creative', () => {
    const presented = presentScrapedProperty({ ...row('submission', 'Example'), source_purpose: 'Submissions' })
    expect(presented.submission_display).toBe('—')
    expect(presented.contract_status_display).toBe('—')
    expect(presented.is_unmapped_creative).toBe(false)
  })

  it('keeps Disney, Marvel, and Star Wars in independent presentation groups', () => {
    expect(groupScrapedProperties([row('1', 'Disney'), row('2', 'Marvel'), row('3', 'Star Wars', 'lucasfilm_dcp')]).map(group => group.name)).toEqual(['Disney', 'Marvel', 'Star Wars'])
  })

  it('loads every page and preserves Lucasfilm as source provenance', async () => {
    let call = 0
    const client = { rpc: async () => ++call === 1
      ? { data: { rows: [row('1', 'Disney')], next_cursor: 'next' }, error: null }
      : { data: { rows: [row('2', 'Star Wars', 'lucasfilm_dcp')], next_cursor: null }, error: null }
    } as unknown as ApiClient
    render(<ScrapedPropertiesTable client={client} />)
    await waitFor(() => expect(screen.getByText('2 of 2 scraped properties')).toBeInTheDocument())
    expect(screen.getByRole('heading', { name: 'Disney' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Star Wars' })).toBeInTheDocument()
    expect(groupScrapedProperties([row('2', 'Star Wars', 'lucasfilm_dcp')])[0].rows[0].source_system).toBe('lucasfilm_dcp')
  })

  it('shows a scoped access denial', async () => {
    const client = { rpc: async () => ({ data: null, error: new Error('licensing manager access required') }) } as unknown as ApiClient
    render(<ScrapedPropertiesTable client={client} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Licensing Manager')
  })
})
