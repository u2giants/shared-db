import type { ColumnRegular } from '@revolist/react-datagrid'
import type { PropertyRow } from './lib/property-rows'

// Issue #1322: an inactive Property stays readable but visibly distinct — the
// same cellProperties mechanism the Scraped Properties grid uses for unmapped
// Creative rows, with a muted treatment instead of red, because "lapsed" is a
// state to see at a glance, not an anomaly to fix.
const inactivePropertyCell = ({ model }: { model: Record<string, unknown> }) =>
  String((model as PropertyRow).status) === 'inactive'
    ? { className: 'inactive-property-cell' }
    : undefined

export const propertyColumns: ColumnRegular[] = [
  { prop: 'name', name: 'Property', size: 240, sortable: true },
  { prop: 'code', name: 'Code', size: 110, sortable: true },
  { prop: 'licensor_name', name: 'Licensor', size: 200, sortable: true },
  { prop: 'licensor_code', name: 'Licensor code', size: 130, sortable: true },
  { prop: 'status', name: 'Status', size: 105, sortable: true },
  { prop: 'character_count', name: 'Characters', size: 105, sortable: true },
  { prop: 'plm_display', name: 'PLM divisions', size: 260 },
  { prop: 'source_display', name: 'Source', size: 280 },
].map(column => ({ ...column, cellProperties: inactivePropertyCell }))
