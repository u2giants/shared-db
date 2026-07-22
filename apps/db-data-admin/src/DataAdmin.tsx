import { RevoGrid, Template, type ColumnRegular, type ColumnTemplateProp } from '@revolist/react-datagrid'
import { ChevronRight, GitMerge, History, LogOut, Pencil, RefreshCw, Search, X } from 'lucide-react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { executeMerge, initialQuery, loadAllRows, loadAudit, loadDetail, loadGridState, loadRows, previewMerge, probeAccess, saveGridState, updateRecord, type AdminRow, type ApiClient, type AuditEvent, type EntityKind, type MergeResult, type QueryState, type UpdateInput } from './lib/data-admin'
import { RecordEditor } from './RecordEditor'
import { MergeDialog } from './MergeDialog'
import { LicensorTree } from './LicensorTree'

type Props = { client: ApiClient; email?: string; onSignOut: () => void }
type HeaderProps = (ColumnTemplateProp | ColumnRegular) & { filters?: Record<string, string>; onFilter?: (prop: string, value: string) => void; scope?: string }

export function FilterHeader(props: HeaderProps) {
  const key = String(props.prop)
  return <div className="filter-header">
    <span>{String(props.name ?? key)}</span>
    <input aria-label={`Filter ${String(props.name ?? key)}`} value={props.filters?.[key] ?? ''}
      onClick={(event) => event.stopPropagation()} onChange={(event) => props.onFilter?.(key, event.target.value)} />
  </div>
}

const baseColumns: ColumnRegular[] = [
  { prop: 'display_name', name: 'Name', size: 260, sortable: true },
  { prop: 'status', name: 'Status', size: 105, sortable: true },
  { prop: 'crm_status', name: 'CRM', size: 105 },
  { prop: 'pm_status', name: 'PM/PIM', size: 105 },
  { prop: 'dam_status', name: 'DAM', size: 105 },
  { prop: 'plm_display', name: 'PLM', size: 115 },
  { prop: 'erp_active', name: 'ERP active', size: 105 },
  { prop: 'alias_count', name: 'Aliases', size: 85 },
  { prop: 'updated_at', name: 'Updated', size: 175, sortable: true },
]

function textMatch(row: AdminRow, filters: Record<string, string>) {
  return Object.entries(filters).every(([key, value]) => !value || String(row[key] ?? '').toLowerCase().includes(value.toLowerCase()))
}

export function DataAdmin({ client, email, onSignOut }: Props) {
  const [kind, setKind] = useState<EntityKind>('customer')
  const [section, setSection] = useState<'entity' | 'taxonomy'>('entity')
  const [query, setQuery] = useState<QueryState>(initialQuery)
  const [filters, setFilters] = useState<Record<string, string>>({})
  const [activeFilters, setActiveFilters] = useState<Record<string, string>>({})
  const [rows, setRows] = useState<AdminRow[]>([])
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [denied, setDenied] = useState(false)
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [audit, setAudit] = useState<AuditEvent[]>([])
  const [editing, setEditing] = useState(false)
  const [merging, setMerging] = useState(false)
  const [channels, setChannels] = useState<Array<{ id: string; name: string }>>([])
  const [dataMode, setDataMode] = useState<'client' | 'server'>('client')
  const version = useRef(0)
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const filterTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const fetchRows = useCallback(async (append = false, override?: QueryState) => {
    setLoading(true); setError(null)
    try {
      const result = dataMode === 'client' && !append ? await loadAllRows(client, kind, override ?? query) : await loadRows(client, kind, override ?? query)
      setRows(current => append ? [...current, ...result.rows] : result.rows)
      setNextCursor(result.nextCursor)
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Data could not be loaded.') }
    finally { setLoading(false) }
  }, [client, dataMode, kind, query])

  useEffect(() => {
    let active = true
    setDenied(false); setRows([]); setFilters({}); setActiveFilters({}); setDetail(null); setLoading(true)
    void (async () => {
      try {
        const allowedChannels = await probeAccess(client)
        if (active) setChannels(allowedChannels)
        const cached = localStorage.getItem(`db-data-admin:${kind}`)
        const remote = await loadGridState(client, kind)
        const restored = { ...initialQuery, ...(cached ? JSON.parse(cached) : {}), ...(remote?.state ?? {}) }
        version.current = remote?.version ?? 0
        if (active) { setQuery(restored); await fetchRows(false, restored) }
      } catch (cause) {
        if (!active) return
        const message = cause instanceof Error ? cause.message : ''
        if (/permission|administrator|access/i.test(message)) setDenied(true); else setError(message || 'Data could not be loaded.')
        setLoading(false)
      }
    })()
    return () => { active = false }
  // fetchRows intentionally excluded: this effect resets when the tab changes.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [client, kind])

  const updateQuery = (patch: Partial<QueryState>) => {
    const next = { ...query, ...patch, cursor: null }
    setQuery(next); localStorage.setItem(`db-data-admin:${kind}`, JSON.stringify(next))
    if (saveTimer.current) clearTimeout(saveTimer.current)
    saveTimer.current = setTimeout(() => void saveGridState(client, kind, next, version.current).then(result => { version.current = result?.version ?? version.current + 1 }).catch(() => setError('Your saved view changed elsewhere. Reload to use the newest version.')), 500)
  }

  const updateFilter = useCallback((prop: string, value: string) => setFilters(current => {
    const next = { ...current, [prop]: value }
    if (filterTimer.current) clearTimeout(filterTimer.current)
    filterTimer.current = setTimeout(() => setActiveFilters(next), 300)
    return next
  }), [])
  const columns = useMemo(() => baseColumns.filter(column => kind === 'customer' || column.prop !== 'plm_display').map(column => ({ ...column, columnTemplate: Template(FilterHeader, { filters, onFilter: updateFilter, scope: kind, key: `${kind}-${String(column.prop)}` }) })), [filters, kind, updateFilter])
  const visibleRows = useMemo(() => rows.filter(row => textMatch(row, activeFilters)).map(row => ({ ...row, plm_display: row.plm_linked === false ? 'Not linked' : row.plm_status == null ? 'Unknown' : row.plm_status === 'ACTIVE' ? 'Active' : 'Inactive' })), [rows, activeFilters])

  const openDetail = async (row: AdminRow) => {
    setDetailLoading(true); setAudit([]); setDetail({ ...row, name: row.display_name ?? row.name })
    try {
      const [loadedDetail, loadedAudit] = await Promise.all([loadDetail(client, kind, row.id), loadAudit(client, kind, row.id)])
      setDetail({ ...row, ...loadedDetail, name: row.display_name ?? row.name }); setAudit(loadedAudit)
    }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Details could not be loaded.') }
    finally { setDetailLoading(false) }
  }

  const saveRecord = async (input: UpdateInput) => {
    if (!detail) throw new Error('No record is selected.')
    const result = await updateRecord(client, kind, String(detail.id), input)
    if (result.success && result.row) {
      setRows(current => current.map(row => row.id === result.row?.id ? { ...row, ...result.row } : row))
      setDetail(current => current ? { ...current, ...result.row, name: result.row?.display_name ?? result.row?.name } : current)
      setAudit(await loadAudit(client, kind, String(detail.id)))
    }
    return result
  }

  const mergeComplete = (result: MergeResult, loserId: string) => {
    setRows(current => current.filter(row => row.id !== loserId).map(row => row.id === result.survivor?.id ? { ...row, ...result.survivor } : row))
    setDetail(current => current && result.survivor ? { ...current, ...result.survivor, name: result.survivor.display_name ?? result.survivor.name } : current)
    setMerging(false)
    if (detail) void loadAudit(client, kind, String(detail.id)).then(setAudit)
  }

  if (denied) return <section className="access-denied" role="alert"><h1>Access denied</h1><p>You are signed in, but DB Data Admin requires an active Administrator grant.</p><button className="secondary" onClick={onSignOut}><LogOut /> Sign out</button></section>

  return <section className="workspace">
    <div className="workspace-bar"><div><strong>{email}</strong><span>Preview database</span></div><button className="secondary" onClick={onSignOut}><LogOut /> Sign out</button></div>
    <nav className="tabs" aria-label="Data type">
      <button className={section === 'entity' && kind === 'customer' ? 'active' : ''} onClick={() => { setSection('entity'); setKind('customer') }}>Customers</button>
      <button className={section === 'entity' && kind === 'vendor' ? 'active' : ''} onClick={() => { setSection('entity'); setKind('vendor') }}>Vendors</button>
      <button className={section === 'taxonomy' ? 'active' : ''} onClick={() => setSection('taxonomy')}>Licensors</button>
    </nav>
    {section === 'taxonomy'
      ? <LicensorTree client={client} />
      : <>
    <div className="controls">
      <label className="search"><Search /><span className="sr-only">Search</span><input placeholder={`Search ${kind}s`} value={query.search} onChange={e => updateQuery({ search: e.target.value })} onKeyDown={e => e.key === 'Enter' && void fetchRows()} /></label>
      <select aria-label="Canonical status" value={query.status} onChange={e => updateQuery({ status: e.target.value })}><option value="">All statuses</option><option>active</option><option>inactive</option></select>
      <select aria-label="Application" value={query.app} onChange={e => updateQuery({ app: e.target.value })}><option value="">All apps</option><option value="crm">CRM</option><option value="pm">PM/PIM</option><option value="dam">DAM</option>{kind === 'customer' && <option value="plm">PLM</option>}</select>
      <select aria-label="Application status" value={query.appStatus} onChange={e => updateQuery({ appStatus: e.target.value })}><option value="">Any app status</option><option value="active">Active</option><option value="inactive">Inactive</option></select>
      {kind === 'customer' && <select aria-label="Channel" value={query.channelId} onChange={e => updateQuery({ channelId: e.target.value })}><option value="">All channels</option>{channels.map(channel => <option key={channel.id} value={channel.id}>{channel.name}</option>)}</select>}
      <select aria-label="Data mode" value={dataMode} onChange={e => setDataMode(e.target.value as 'client' | 'server')}><option value="client">Client mode (&lt;5,000)</option><option value="server">Server mode</option></select>
      <label className="check"><input type="checkbox" checked={query.includeInactive} onChange={e => updateQuery({ includeInactive: e.target.checked })} /> Include inactive</label>
      <button className="icon-button" aria-label="Refresh" onClick={() => void fetchRows()}><RefreshCw /></button>
    </div>
    {error && <div className="inline-error" role="alert">{error}</div>}
    <div className="grid-wrap" aria-busy={loading}>
      <RevoGrid theme="material" readonly accessible resize columns={columns} source={visibleRows} rowHeaders onBeforecellfocus={(event) => { const row = visibleRows[event.detail.rowIndex]; if (row) void openDetail(row) }} />
      {loading && <div className="grid-loading">Loading…</div>}
    </div>
    <footer className="grid-footer"><span>{visibleRows.length} loaded</span>{nextCursor && <button className="secondary" disabled={loading} onClick={() => { const next = { ...query, cursor: nextCursor }; setQuery(next); void fetchRows(true, next) }}>Load more <ChevronRight /></button>}</footer>
    {detail && <aside className="detail-panel" aria-label={`${kind} details`}><button className="close" aria-label="Close details" onClick={() => { setDetail(null); setEditing(false); setMerging(false) }}><X /></button><h2>{String(detail.name ?? 'Details')}</h2><div className="detail-actions"><button className="primary edit-button" onClick={() => setEditing(true)}><Pencil /> Edit record</button><button className="secondary" onClick={() => setMerging(true)}><GitMerge /> Merge duplicate</button></div>{detailLoading ? <p>Loading details…</p> : <><h3>Aliases</h3><pre>{JSON.stringify(detail.aliases ?? [], null, 2)}</pre><h3>Source references</h3><pre>{JSON.stringify(detail.source_refs ?? [], null, 2)}</pre><h3 className="history-heading"><History /> Audit history</h3>{audit.length === 0 ? <p className="muted">No audited changes yet.</p> : <ol className="audit-list">{audit.map(event => <li key={event.id} className={event.succeeded ? '' : 'failed'}><strong>{event.succeeded ? event.action === 'merge' ? 'Records merged' : 'Change saved' : `Failed: ${event.error_code}`}</strong><span>{new Date(event.occurred_at).toLocaleString()} · {event.actor_label ?? 'Administrator'}</span><p>{event.reason}</p></li>)}</ol>}</>}</aside>}
    {editing && detail && <RecordEditor kind={kind} row={detail as AdminRow} channels={channels} onCancel={() => setEditing(false)} onSave={saveRecord} />}
    {merging && detail && <MergeDialog kind={kind} survivor={detail as AdminRow} candidates={rows.filter(row => row.id !== detail.id)} onCancel={() => setMerging(false)} onPreview={loserId => previewMerge(client, kind, String(detail.id), loserId)} onMerge={(loserId, token, reason, resolutions) => executeMerge(client, kind, String(detail.id), loserId, token, reason, resolutions)} onMerged={mergeComplete} />}
    </>}
  </section>
}
