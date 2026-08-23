import { vi } from 'vitest'
import type { ApiClient, LicensorTreeResult } from '../lib/data-admin'

function queryResult(data: unknown) {
  const result = { data, error: null }
  const query: Record<string, unknown> = {
    select: () => query,
    order: () => query,
    eq: () => query,
    range: () => query,
    then: (resolve: (value: typeof result) => unknown) => Promise.resolve(resolve(result)),
  }
  return query
}

export function makeUniverseBClient(payload: LicensorTreeResult): ApiClient {
  const licensors = payload.licensors.map((licensor, index) => ({
    licenseList_id: index + 1,
    licenseList_code: licensor.code,
    licenseList_title: licensor.name,
    licenseList_status: licensor.status,
  }))
  let nextPropertyId = 1
  const associations: Array<{ property_id: number; character_id: number }> = []
  const properties = payload.licensors.flatMap((licensor, licensorIndex) => licensor.properties.map(property => {
    const id = nextPropertyId++
    for (let i = 0; i < (property.character_count ?? 0); i += 1) associations.push({ property_id: id, character_id: associations.length + 1 })
    return { id, licensor_id: licensorIndex + 1, name: property.name, source_licensed_property_id: property.code, type: 'PROPERTY', updated_at: property.updated_at ?? payload.snapshot.snapshot_at }
  }))
  for (const property of payload.orphan_properties) {
    properties.push({ id: nextPropertyId++, licensor_id: 999999, name: property.name, source_licensed_property_id: property.code, type: 'PROPERTY', updated_at: property.updated_at ?? payload.snapshot.snapshot_at })
  }
  const schema = vi.fn((name: string) => ({
    rpc: vi.fn(async () => ({ data: null, error: null })),
    from: vi.fn((table: string) => queryResult(table === 'licenseList' ? licensors : table === 'properties_and_characters' ? properties : associations)),
    schema: name,
  }))
  return { schema } as unknown as ApiClient
}

export function makeFailingUniverseBClient(message: string): ApiClient {
  return { schema: vi.fn(() => ({ rpc: vi.fn(async () => ({ data: null, error: new Error(message) })) })) } as unknown as ApiClient
}
