import type { createSupabase } from './supabase'

export type EntityKind = 'customer' | 'vendor'
export type AdminRow = Record<string, unknown> & { id: string; display_name?: string; name?: string }
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
