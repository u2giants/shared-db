import { describe, expect, it } from 'vitest'
import { flattenProperties, formatPlmContext, formatSourceRefs } from './property-rows'
import type { LoadedTree } from './data-admin'

const tree: Pick<LoadedTree, 'licensors' | 'orphanProperties'> = {
  licensors: [
    {
      id: 'l-marvel', name: 'Marvel', code: 'MRV', status: 'active',
      property_count: 2, source_refs: [], plm_context: [],
      properties: [
        {
          id: 'p-avengers', name: 'Avengers', code: 'AVG', status: 'active', character_count: 5,
          source_refs: [{ source_system: 'designflow_plm', source_table: 'merchGroup', source_id: 'x', source_code: 'AVG', source_name: null }],
          plm_context: [{ plm_id: 'pa', division_code: 'CW001', mg_code: 'AVG', mg_type: 'property', mg_category: 'licensed' }],
        },
        {
          id: 'p-spider', name: 'Spider-Man', code: null, status: 'potential', character_count: 0,
          source_refs: [], plm_context: [],
        },
      ],
    },
    {
      id: 'l-disney', name: 'Disney', code: 'DS', status: 'active',
      property_count: 0, source_refs: [], plm_context: [], properties: [],
    },
  ],
  orphanProperties: [
    { id: 'o-1', name: 'Mystery IP', code: 'MYS', status: 'active', licensor_id: null, character_count: 0, source_refs: [], plm_context: [] },
  ],
}

describe('flattenProperties', () => {
  it('emits one row per property, carrying its licensor', () => {
    const rows = flattenProperties(tree)
    expect(rows.map(row => row.id)).toEqual(['p-avengers', 'p-spider', 'o-1'])
    expect(rows[0].licensor_name).toBe('Marvel')
    expect(rows[0].licensor_code).toBe('MRV')
    expect(rows[0].character_count).toBe(5)
    expect(rows[1].code).toBeNull()
    expect(rows[1].status).toBe('potential')
  })

  it('includes orphan properties, marked and parented to "(no licensor)"', () => {
    const orphan = flattenProperties(tree).find(row => row.id === 'o-1')
    expect(orphan?.is_orphan).toBe(true)
    expect(orphan?.licensor_name).toBe('(no licensor)')
    expect(orphan?.licensor_code).toBeNull()
  })

  it('never drops a property, so the row count matches the tree', () => {
    const nested = tree.licensors.reduce((total, licensor) => total + licensor.properties.length, 0)
    expect(flattenProperties(tree)).toHaveLength(nested + tree.orphanProperties.length)
  })

  it('returns no rows for an empty tree', () => {
    expect(flattenProperties({ licensors: [], orphanProperties: [] })).toEqual([])
  })
})

describe('provenance formatting', () => {
  it('summarises source references', () => {
    expect(formatSourceRefs(tree.licensors[0].properties[0])).toBe('designflow_plm/merchGroup · AVG')
  })

  it('summarises PLM context', () => {
    expect(formatPlmContext(tree.licensors[0].properties[0])).toBe('CW001 · property · AVG')
  })

  it('renders empty provenance as an empty string, not "undefined"', () => {
    expect(formatSourceRefs(tree.licensors[0].properties[1])).toBe('')
    expect(formatPlmContext(tree.licensors[0].properties[1])).toBe('')
  })
})
