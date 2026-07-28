import type { AdminRow, LoadedTree, PropertyNode, TaxonomyNode } from './data-admin'

/**
 * Flat Property grid rows built from the Licensor -> Property tree contract.
 *
 * There is deliberately NO `db_data_admin_property_list` RPC. The existing
 * `api.db_data_admin_licensor_property_tree` already returns every property
 * with its parent, code, status, character count, provenance and PLM context,
 * plus the complete orphan list, so the flat table is a presentation of the
 * same contract rather than a second, drift-prone read path.
 *
 * The table is read-only in v1 for the same reason the tree is: DesignFlow owns
 * the Licensor -> Property edge.
 *
 * No "Updated" column: the tree contract carries `updated_at` on licensors and
 * on orphan properties, but NOT on properties nested under a licensor. Showing
 * a column that is blank for almost every row would read as missing data, so it
 * is left out until the contract carries it for every property.
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
}

/** `MV · Marvel/property · 1234` style provenance summary, one chip per ref. */
export function formatSourceRefs(node: TaxonomyNode): string {
  return node.source_refs
    .map(ref => [ref.source_system, ref.source_table ? `/${ref.source_table}` : '', ref.source_code ? ` · ${ref.source_code}` : ''].join(''))
    .join(', ')
}

/** `EDGEHOME · MG06 · MV` style PLM context summary, one entry per row. */
export function formatPlmContext(node: TaxonomyNode): string {
  return node.plm_context
    .map(entry => [entry.division_code ?? '—', entry.mg_type ?? '', entry.mg_code ?? ''].filter(Boolean).join(' · '))
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
