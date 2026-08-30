import { Template, type ColumnRegular } from '@revolist/react-datagrid'
import { ReviewTextCell } from './ReviewTextCell'
import type { ScrapedPropertyRow } from './lib/data-admin'

const reviewTextTemplate = Template(ReviewTextCell)

const unmappedCreativeCell = ({ model }: { model: Record<string, unknown> }) => (model as ScrapedPropertyRow).is_unmapped_creative
  ? { className: 'unmapped-creative-cell', style: { background: '#fff0f0', color: '#8a1c1c' } }
  : undefined

export const scrapedPropertiesColumns: ColumnRegular[] = [
  { prop: 'display_label', name: 'Property', size: 260, sortable: true },
  { prop: 'submission_display', name: 'Authoritative Submissions', size: 280, sortable: true },
  { prop: 'mapping_state', name: 'Mapping', size: 130, sortable: true },
  { prop: 'contract_status_display', name: 'Contract status', size: 220, sortable: true },
  { prop: 'review_reason', name: 'Review reason', size: 260, sortable: true, cellTemplate: reviewTextTemplate },
  { prop: 'evidence_basis', name: 'Evidence basis', size: 240, sortable: true, cellTemplate: reviewTextTemplate },
  { prop: 'review_guidance', name: 'Decision guidance', size: 280, sortable: true, cellTemplate: reviewTextTemplate },
  { prop: 'source_system', name: 'Source system', size: 190, sortable: true },
  { prop: 'source_property_id', name: 'Source ID', size: 180, sortable: true },
  { prop: 'source_status', name: 'Source status', size: 130, sortable: true },
  { prop: 'provenance_kind', name: 'Provenance', size: 220, sortable: true },
  { prop: 'source_purpose', name: 'Purpose', size: 210, sortable: true },
  { prop: 'source_table', name: 'Source table', size: 210, sortable: true },
  { prop: 'latest_seen_at', name: 'Latest seen', size: 180, sortable: true },
  { prop: 'capture_marker', name: 'Capture marker', size: 180, sortable: true },
].map(column => ({ ...column, cellProperties: unmappedCreativeCell }))
