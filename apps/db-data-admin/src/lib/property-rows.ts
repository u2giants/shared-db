import type { AdminRow, LoadedTree, PlmContextEntry, PropertyNode, TaxonomyNode } from './data-admin'

/**
 * Flat Property grid rows built from the Licensor -> Property tree contract.
 *
 * There is deliberately NO `db_data_admin_property_list` RPC. The existing
 * `api.db_data_admin_licensor_property_tree` already returns every property
 * with its parent, code, status, character count, provenance and PLM context,
 * plus the complete orphan list, so the flat table is a presentation of the
 * same contract rather than a second, drift-prone read path.
 *
 * The table stays read-only for everything except status (issue #1322): the
 * Licensor -> Property edge is still DesignFlow's, and descriptive fields have
 * no guarded write path here.
 *
 * No "Updated" column is shown: the row's `updated_at` is carried (the
 * status-change RPC needs it as the optimistic-concurrency token, issue #1322)
 * but a timestamp column adds noise a licensing manager does not act on.
 */
export type PropertyRow = AdminRow & {
  id: string
  name: string
  code: string | null
  status: string
  licensor_name: string
  licensor_code: string | null
  character_count: number
  source_display: string
  plm_display: string
  is_orphan: boolean
  /** Concurrency token for api.db_data_admin_set_property_status (issue #1322). */
  updated_at: string | null
}

/** `MV · Marvel/property · 1234` style provenance summary, one chip per ref. */
export function formatSourceRefs(node: TaxonomyNode): string {
  return node.source_refs
    .map(ref => [ref.source_system, ref.source_table ? `/${ref.source_table}` : '', ref.source_code ? ` · ${ref.source_code}` : ''].join(''))
    .join(', ')
}

/**
 * Which PLM divisions carry this record, and under which merch-group code:
 * `POP Lic (CW001) · GS, Spruce Lic (SP001) · GS`.
 *
 * `mg_type` is deliberately not shown. It is a fixed literal per branch of the
 * tree contract ('property' on every property, 'licensor' on every licensor),
 * so printing it added the same dead word to every row.
 *
 * A division with no lookup row falls back to its raw PLM id rather than
 * rendering an empty chip, so an unmapped division stays visible.
 */
export function formatDivision(entry: PlmContextEntry): string {
  const name = entry.division_name?.trim()
  const external = entry.division_external_code?.trim()
  if (name && external) return `${name} (${external})`
  if (name) return name
  if (external) return external
  return entry.division_code ?? '—'
}

export function formatPlmContext(node: TaxonomyNode): string {
  return node.plm_context
    .map(entry => [formatDivision(entry), entry.mg_code ?? ''].filter(Boolean).join(' · '))
    .join(', ')
}

function toRow(property: PropertyNode, licensorName: string, licensorCode: string | null, isOrphan: boolean): PropertyRow {
  return {
    id: property.id,
    name: property.name,
    code: property.code ?? null,
    status: property.status,
    licensor_name: licensorName,
    licensor_code: licensorCode,
    character_count: property.character_count ?? 0,
    source_display: formatSourceRefs(property),
    plm_display: formatPlmContext(property),
    is_orphan: isOrphan,
    updated_at: property.updated_at ?? null,
  }
}

/**
 * Every property in the tree as one flat row set, orphans included and clearly
 * marked. Orphans are an anomaly the tree surfaces loudly; hiding them here
 * would make the table quietly disagree with the tree's own reconciliation
 * counts, so they are listed with an explicit "(no licensor)" parent.
 */
export function flattenProperties(tree: Pick<LoadedTree, 'licensors' | 'orphanProperties'>): PropertyRow[] {
  const rows: PropertyRow[] = []
  for (const licensor of tree.licensors) {
    for (const property of licensor.properties) {
      rows.push(toRow(property, licensor.name, licensor.code ?? null, false))
    }
  }
  for (const orphan of tree.orphanProperties) {
    rows.push(toRow(orphan, '(no licensor)', null, true))
  }
  return rows
}
