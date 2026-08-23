import type { createSupabase } from './supabase'

export type EntityKind = 'customer' | 'vendor'
export type AdminRow = Record<string, unknown> & { id: string; display_name?: string; name?: string }
export type UpdateInput = {
  expectedUpdatedAt: string; reason: string; displayName?: string | null; status?: string | null
  app?: 'crm' | 'pm' | 'dam' | null; appStatus?: 'active' | 'inactive' | null; channelIds?: string[] | null
}
export type UpdateResult = { success: boolean; code?: string; message?: string; row?: AdminRow; current?: AdminRow; audit_id?: string; idempotent_replay?: boolean }
export type AuditEvent = { id: string; action: string; reason: string; actor_label?: string; occurred_at: string; succeeded: boolean; error_code?: string; old_snapshot?: Record<string, unknown>; new_snapshot?: Record<string, unknown> }
export type MergeConflict = { key: string; app: string; field: string; survivor: unknown; loser: unknown }
export type MergeMovingAlias = { alias: string; alias_type?: string | null; source_system?: string | null; origin: 'existing_alias' | 'loser_name' }
export type MergeMovingSourceRef = { source_system: string; source_table?: string | null; source_id?: string | null; source_code?: string | null; source_name?: string | null }
export type MergePreview = { entity_type: EntityKind; survivor: AdminRow; loser: AdminRow; affected_counts: Record<string, number>; conflicts: MergeConflict[]; moving_aliases?: MergeMovingAlias[]; moving_source_refs?: MergeMovingSourceRef[] }
export type MergePreviewResult = { success: boolean; code?: string; message?: string; preview?: MergePreview; preview_token?: string }
export type MergeResult = { success: boolean; code?: string; message?: string; survivor?: AdminRow; audit_id?: string; idempotent_replay?: boolean; current_preview?: MergePreviewResult }
export type QueryState = {
  search: string; status: string; app: string; appStatus: string; includeInactive: boolean
  channelId: string; sort: string; sortDir: 'asc' | 'desc'; cursor: string | null; pageSize: number
}

export const initialQuery: QueryState = {
  search: '', status: '', app: '', appStatus: '', includeInactive: false,
  channelId: '', sort: 'display_name', sortDir: 'asc', cursor: null, pageSize: 200,
}

export function toRpcParams(kind: EntityKind, query: QueryState) {
  return {
    p_search: query.search || null,
    p_status: query.status || null,
    p_app: query.app || null,
    p_app_status: query.appStatus || null,
    p_include_inactive: query.includeInactive,
    p_sort: query.sort,
    p_sort_dir: query.sortDir,
    p_cursor: query.cursor,
    p_page_size: query.pageSize,
    ...(kind === 'customer' ? { p_channel_id: query.channelId || null } : {}),
  }
}

export type ApiClient = ReturnType<typeof createSupabase>

export async function probeAccess(client: ApiClient) {
  const { data, error } = await client.rpc('db_data_admin_channel_list')
  if (error) throw error
  return (data ?? []) as Array<{ id: string; name: string }>
}

export async function loadRows(client: ApiClient, kind: EntityKind, query: QueryState) {
  const { data, error } = await client.rpc(`db_data_admin_${kind}_list`, toRpcParams(kind, query))
  if (error) throw error
  const payload = (data ?? {}) as { rows?: AdminRow[]; next_cursor?: string | null }
  return { rows: payload.rows ?? [], nextCursor: payload.next_cursor ?? null }
}

export async function loadAllRows(client: ApiClient, kind: EntityKind, query: QueryState, limit = 5000) {
  const rows: AdminRow[] = []
  let cursor: string | null = null
  do {
    const page = await loadRows(client, kind, { ...query, cursor, pageSize: 200 })
    rows.push(...page.rows); cursor = page.nextCursor
  } while (cursor && rows.length < limit)
  return { rows, nextCursor: cursor }
}

// Bounded candidate search for the merge dialog: a legitimate duplicate may not
// be in the currently loaded grid page (server mode, or beyond the client-mode
// cap), so the dialog can search the full entity by name through the same
// protected list RPC. Bounded to a single small page — never an unbounded scan.
export async function searchMergeCandidates(client: ApiClient, kind: EntityKind, term: string, excludeId: string) {
  const query: QueryState = { ...initialQuery, search: term, includeInactive: true, pageSize: 25 }
  const { rows } = await loadRows(client, kind, query)
  return rows.filter(row => row.id !== excludeId)
}

export async function loadDetail(client: ApiClient, kind: EntityKind, id: string) {
  const { data, error } = await client.rpc(`db_data_admin_${kind}_detail`, { p_id: id })
  if (error) throw error
  return data as Record<string, unknown>
}

export async function updateRecord(client: ApiClient, kind: EntityKind, id: string, input: UpdateInput) {
  const params = {
    [`p_${kind === 'customer' ? 'customer' : 'vendor'}_id`]: id,
    p_expected_updated_at: input.expectedUpdatedAt,
    p_operation_id: crypto.randomUUID(),
    p_reason: input.reason,
    p_display_name: input.displayName ?? null,
    p_status: input.status ?? null,
    p_app: input.app ?? null,
    p_app_status: input.appStatus ?? null,
    ...(kind === 'customer' ? { p_channel_ids: input.channelIds ?? null } : {}),
  }
  const { data, error } = await client.rpc(`db_data_admin_update_${kind}`, params)
  if (error) throw error
  return data as UpdateResult
}

export async function loadAudit(client: ApiClient, kind: EntityKind, id: string) {
  const { data, error } = await client.rpc('db_data_admin_audit_list', {
    p_entity_type: kind, p_entity_id: id, p_action: null, p_actor_profile_id: null,
    p_since: null, p_until: null, p_cursor: null, p_page_size: 50,
  })
  if (error) throw error
  return ((data as { rows?: AuditEvent[] } | null)?.rows ?? [])
}

export async function previewMerge(client: ApiClient, kind: EntityKind, survivorId: string, loserId: string) {
  const { data, error } = await client.rpc(`db_data_admin_preview_${kind}_merge`, { p_survivor_id: survivorId, p_loser_id: loserId })
  if (error) throw error
  return data as MergePreviewResult
}

export async function executeMerge(client: ApiClient, kind: EntityKind, survivorId: string, loserId: string, previewToken: string, reason: string, resolutions: Record<string, 'survivor' | 'loser'>) {
  const { data, error } = await client.rpc(`db_data_admin_merge_${kind}`, {
    p_survivor_id: survivorId, p_loser_id: loserId, p_preview_token: previewToken,
    p_operation_id: crypto.randomUUID(), p_reason: reason, p_resolutions: resolutions,
  })
  if (error) throw error
  return data as MergeResult
}

export async function loadGridState(client: ApiClient, kind: EntityKind) {
  const { data, error } = await client.rpc('db_data_admin_grid_state_get', { p_entity_type: kind, p_view_key: 'default' })
  if (error) throw error
  return data as { state?: Partial<QueryState>; version?: number } | null
}

export async function saveGridState(client: ApiClient, kind: EntityKind, state: QueryState, version: number) {
  const { data, error } = await client.rpc('db_data_admin_grid_state_upsert', {
    p_entity_type: kind, p_view_key: 'default', p_state: state, p_expected_version: version || null,
  })
  if (error) throw error
  const result = data as { ok?: boolean; code?: string; current_version?: number; version?: number } | null
  if (result?.ok === false) throw new Error(result.code === 'version_conflict' ? `Saved view conflict at version ${result.current_version ?? 'unknown'}` : 'Saved view could not be updated')
  return result
}

// ---- Step 10: read-only Licensor -> Property tree ---------------------------

export type TaxonomySourceRef = {
  source_system: string; source_table: string; source_id: string
  source_code: string | null; source_name: string | null
}
export type PlmContextEntry = {
  plm_id: string | null; division_code: string | null; mg_code: string | null
  mg_type: string | null; mg_category: string | null
  // Added by migration 20260728171500 so the UI can name a division instead of
  // printing its raw PLM id. Optional because a division id with no lookup row
  // yields nulls rather than dropping the entry.
  division_name?: string | null; division_external_code?: string | null
}
export type TaxonomyNode = {
  id: string; name: string; code: string | null; status: string
  character_count?: number; licensor_id?: string | null
  source_refs: TaxonomySourceRef[]; plm_context: PlmContextEntry[]
  updated_at?: string
}
export type PropertyNode = TaxonomyNode
export type LicensorNode = TaxonomyNode & { property_count: number; properties: PropertyNode[] }
export type TreeSnapshot = {
  snapshot_at: string; store: string; source_system: string
  feeder_last_sync_at: string | null; feeder_last_run_status: string | null
  feeder_days_stale: number | null; feeder_available: boolean
  live_upstream_reconciliation: boolean; note: string
}
export type TreeReconciliation = {
  licensor_count: number; active_licensor_count: number
  property_count: number; active_property_count: number
  properties_with_licensor: number; orphan_property_count: number
  expected_orphan_count_is_zero: boolean; partition_reconciles: boolean
}
export type LicensorTreeResult = {
  snapshot: TreeSnapshot; reconciliation: TreeReconciliation
  licensors: LicensorNode[]; orphan_properties: PropertyNode[]
  next_cursor: string | null; page_size: number
}
export type LoadedTree = {
  snapshot: TreeSnapshot; reconciliation: TreeReconciliation
  licensors: LicensorNode[]; orphanProperties: PropertyNode[]
}

type UniverseBLicensor = {
  licenseList_id: number
  licenseList_code: string | null
  licenseList_title: string | null
  licenseList_status: string | null
}
type UniverseBEntity = {
  id: number
  licensor_id: number
  name: string
  source_licensed_property_id: string | null
  type: string
  updated_at: string
}
type UniverseBAssociation = { property_id: number; character_id: number }

function normalizeStatus(value: string | null) {
  const status = value?.trim().toLowerCase()
  return status === 'inactive' ? 'inactive' : status || 'active'
}

async function loadUniverseBAssociations(client: ApiClient) {
  const rows: UniverseBAssociation[] = []
  const pageSize = 1000
  for (let start = 0; ; start += pageSize) {
    const { data, error } = await client.schema('core')
      .from('property_character_associations')
      .select('property_id,character_id')
      .range(start, start + pageSize - 1)
    if (error) throw error
    const page = (data ?? []) as UniverseBAssociation[]
    rows.push(...page)
    if (page.length < pageSize) return rows
  }
}

// Universe B is a mixed portal-source table. Only PROPERTY rows become rows in
// these screens; CHARACTER rows are represented solely by the association
// count. The parent edge is its declared integer FK to core."licenseList" --
// never a name/code guess against the disjoint UUID core.licensor universe.
export async function loadLicensorTree(client: ApiClient, params: { includeInactive?: boolean } = {}) {
  const gate = await client.schema('app').rpc('require_licensing_manager_access')
  if (gate.error) throw gate.error

  const [licensorResult, propertyResult, associations] = await Promise.all([
    client.schema('core').from('licenseList')
      .select('licenseList_id,licenseList_code,licenseList_title,licenseList_status')
      .order('licenseList_title'),
    client.schema('core').from('properties_and_characters')
      .select('id,licensor_id,name,source_licensed_property_id,type,updated_at')
      .eq('type', 'PROPERTY').order('name'),
    loadUniverseBAssociations(client),
  ])
  if (licensorResult.error) throw licensorResult.error
  if (propertyResult.error) throw propertyResult.error

  const rawLicensors = (licensorResult.data ?? []) as UniverseBLicensor[]
  const rawProperties = ((propertyResult.data ?? []) as UniverseBEntity[]).filter(row => row.type === 'PROPERTY')
  const characterCounts = new Map<number, number>()
  for (const association of associations) {
    characterCounts.set(association.property_id, (characterCounts.get(association.property_id) ?? 0) + 1)
  }

  const propertiesByLicensor = new Map<number, PropertyNode[]>()
  for (const property of rawProperties) {
    const node: PropertyNode = {
      id: String(property.id), name: property.name, code: property.source_licensed_property_id,
      status: 'active', licensor_id: String(property.licensor_id),
      character_count: characterCounts.get(property.id) ?? 0,
      source_refs: property.source_licensed_property_id ? [{
        source_system: 'licensor_portal', source_table: 'core.properties_and_characters',
        source_id: property.source_licensed_property_id, source_code: property.source_licensed_property_id, source_name: property.name,
      }] : [],
      plm_context: [], updated_at: property.updated_at,
    }
    const bucket = propertiesByLicensor.get(property.licensor_id) ?? []
    bucket.push(node); propertiesByLicensor.set(property.licensor_id, bucket)
  }

  const allLicensors: LicensorNode[] = rawLicensors.map(licensor => {
    const properties = propertiesByLicensor.get(licensor.licenseList_id) ?? []
    return {
      id: String(licensor.licenseList_id), name: licensor.licenseList_title || `(Licensor ${licensor.licenseList_id})`,
      code: licensor.licenseList_code, status: normalizeStatus(licensor.licenseList_status),
      property_count: properties.length, properties, source_refs: [], plm_context: [],
    }
  })
  const licensors = params.includeInactive ? allLicensors : allLicensors.filter(licensor => licensor.status !== 'inactive')
  const knownLicensors = new Set(rawLicensors.map(licensor => licensor.licenseList_id))
  const orphanProperties = rawProperties
    .filter(property => !knownLicensors.has(property.licensor_id))
    .map(property => propertiesByLicensor.get(property.licensor_id)?.find(node => node.id === String(property.id)))
    .filter((property): property is PropertyNode => Boolean(property))
  const parentedProperties = rawProperties.length - orphanProperties.length
  const now = new Date().toISOString()
  return {
    snapshot: {
      snapshot_at: now, store: 'core.licenseList / core.properties_and_characters (Universe B)',
      source_system: 'licensor_portal', feeder_last_sync_at: null, feeder_last_run_status: null,
      feeder_days_stale: null, feeder_available: false, live_upstream_reconciliation: false,
      note: 'Licensor-portal Property rows only. Character-grain rows are never listed as Properties; character totals come from the declared association table.',
    },
    reconciliation: {
      licensor_count: rawLicensors.length,
      active_licensor_count: rawLicensors.filter(licensor => normalizeStatus(licensor.licenseList_status) !== 'inactive').length,
      property_count: rawProperties.length, active_property_count: rawProperties.length,
      properties_with_licensor: parentedProperties,
      orphan_property_count: orphanProperties.length,
      expected_orphan_count_is_zero: orphanProperties.length === 0,
      partition_reconciles: rawProperties.length === parentedProperties + orphanProperties.length,
    },
    licensors,
    orphanProperties,
  }
}
