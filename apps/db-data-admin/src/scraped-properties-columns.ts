import type { ColumnRegular } from '@revolist/react-datagrid'

export const scrapedPropertiesColumns: ColumnRegular[] = [
  { prop: 'display_label', name: 'Property', size: 260, sortable: true },
  { prop: 'review_reason', name: 'Review reason', size: 300, sortable: true },
  { prop: 'evidence_basis', name: 'Evidence basis', size: 240, sortable: true },
  { prop: 'review_guidance', name: 'Decision guidance', size: 360, sortable: true },
  { prop: 'source_system', name: 'Source system', size: 190, sortable: true },
  { prop: 'source_property_id', name: 'Source ID', size: 180, sortable: true },
  { prop: 'source_status', name: 'Source status', size: 130, sortable: true },
  { prop: 'provenance_kind', name: 'Provenance', size: 220, sortable: true },
  { prop: 'source_purpose', name: 'Purpose', size: 210, sortable: true },
  { prop: 'source_table', name: 'Source table', size: 210, sortable: true },
  { prop: 'latest_seen_at', name: 'Latest seen', size: 180, sortable: true },
  { prop: 'capture_marker', name: 'Capture marker', size: 180, sortable: true },
]
