import { render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ScrapedPropertiesTable } from './ScrapedPropertiesTable'
import { groupScrapedProperties, type ApiClient, type ScrapedPropertyRow } from './lib/data-admin'
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
  it('puts review decision context immediately after Property', () => {
    expect(scrapedPropertiesColumns.slice(0, 4).map(column => column.name)).toEqual([
      'Property',
      'Review reason',
      'Evidence basis',
      'Decision guidance',
    ])
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
