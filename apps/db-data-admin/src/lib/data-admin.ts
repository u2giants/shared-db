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
export type MergePreview = { entity_type: EntityKind; survivor: AdminRow; loser: AdminRow; affected_counts: Record<string, number>; conflicts: MergeConflict[] }
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
