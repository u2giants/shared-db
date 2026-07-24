import { RevoGrid, Template, type ColumnRegular, type ColumnTemplateProp } from '@revolist/react-datagrid'
import { ChevronRight, Filter, GitMerge, History, LogOut, Pencil, RefreshCw, Search, X } from 'lucide-react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { executeMerge, initialQuery, loadAllRows, loadAudit, loadDetail, loadGridState, loadRows, previewMerge, probeAccess, saveGridState, searchMergeCandidates, updateRecord, type AdminRow, type ApiClient, type AuditEvent, type EntityKind, type MergeResult, type QueryState, type UpdateInput } from './lib/data-admin'
import {
  BLANK_VALUE,
  formatFilterOptionLabel,
  getCellDisplayValue,
  getDistinctColumnValues,
  rowMatchesFilters,
  toggleSetFilterValue,
} from './lib/grid-filters'
import { RecordEditor } from './RecordEditor'
import { MergeDialog } from './MergeDialog'
import { LicensorTree } from './LicensorTree'

type Props = { client: ApiClient; email?: string; onSignOut: () => void }

export type HeaderProps = (ColumnTemplateProp | ColumnRegular) & {
  filters?: Record<string, string>
  onFilter?: (prop: string, value: string) => void
  setFilters?: Record<string, ReadonlySet<string> | undefined | null>
  onSetFilter?: (prop: string, selected: Set<string> | null) => void
  distinctValues?: Record<string, string[]>
  scope?: string
}

/**
 * Multi-filter column header: Text Filter (controlled input) + Set Filter (popover).
 * Props `filters` / `onFilter` keep the existing text-filter contract used by tests.
 */
export function FilterHeader(props: HeaderProps) {
  const key = String(props.prop)
  const label = String(props.name ?? key)
  const [open, setOpen] = useState(false)
  const [listSearch, setListSearch] = useState('')
  const [popoverPos, setPopoverPos] = useState<{ top: number; left: number } | null>(null)
  const [acOpen, setAcOpen] = useState(false)
  const [acPos, setAcPos] = useState<{ top: number; left: number; width: number } | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const popoverRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const acRef = useRef<HTMLUListElement>(null)
  const allValues = useMemo(() => props.distinctValues?.[key] ?? [], [props.distinctValues, key])
  const selected = props.setFilters?.[key]
  const isSetActive = selected != null
  const checked = selected == null ? null : selected
  const textValue = props.filters?.[key] ?? ''

  const closePopover = useCallback(() => { setOpen(false); setListSearch('') }, [])
  const closeAutocomplete = useCallback(() => setAcOpen(false), [])

  // Typeahead suggestions for the header text input: the column's distinct
  // values (blanks excluded — those belong to the Set Filter) that contain the
  // typed text. Portalled like the popover so RevoGrid cannot clip it.
  const suggestions = useMemo(() => {
    const q = textValue.trim().toLowerCase()
    if (!q) return []
    return allValues
      .filter(value => value !== BLANK_VALUE)
      .filter(value => value.toLowerCase().includes(q) && value.toLowerCase() !== q)
      .slice(0, 8)
  }, [allValues, textValue])

  const positionAutocomplete = useCallback(() => {
    const rect = inputRef.current?.getBoundingClientRect()
    if (rect) setAcPos({ top: rect.bottom + 2, left: rect.left, width: rect.width })
  }, [])

  // The popover is portalled to document.body so RevoGrid's header overflow
  // cannot clip it; position it under the funnel button from its screen rect.
  const positionPopover = useCallback(() => {
    const rect = buttonRef.current?.getBoundingClientRect()
    if (rect) setPopoverPos({ top: rect.bottom + 2, left: rect.left })
  }, [])

  useEffect(() => {
    if (!open) return
    // Because the popover lives outside rootRef (in a portal), test both the
    // header root and the popover element before treating a click as "outside".
    const onPointerDown = (event: MouseEvent) => {
      const target = event.target as Node
      if (rootRef.current?.contains(target) || popoverRef.current?.contains(target)) return
      closePopover()
    }
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === 'Escape') closePopover() }
    // A scroll or resize would leave the portalled popover detached from its
    // button, so reposition (capture:true also catches RevoGrid's inner scroll).
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    window.addEventListener('resize', positionPopover)
    window.addEventListener('scroll', positionPopover, true)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('resize', positionPopover)
      window.removeEventListener('scroll', positionPopover, true)
    }
  }, [open, closePopover, positionPopover])

  useEffect(() => {
    if (!acOpen) return
    const onPointerDown = (event: MouseEvent) => {
      const target = event.target as Node
      if (inputRef.current?.contains(target) || acRef.current?.contains(target)) return
      closeAutocomplete()
    }
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === 'Escape') closeAutocomplete() }
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKeyDown)
    window.addEventListener('resize', positionAutocomplete)
    window.addEventListener('scroll', positionAutocomplete, true)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('resize', positionAutocomplete)
      window.removeEventListener('scroll', positionAutocomplete, true)
    }
  }, [acOpen, closeAutocomplete, positionAutocomplete])

  const filteredValues = useMemo(() => {
    const q = listSearch.trim().toLowerCase()
    if (!q) return allValues
    return allValues.filter(value => formatFilterOptionLabel(value).toLowerCase().includes(q))
  }, [allValues, listSearch])

  const isChecked = (value: string) => (checked == null ? true : checked.has(value))

  const applyToggle = (value: string) => {
    props.onSetFilter?.(key, toggleSetFilterValue(selected, allValues, value))
  }

  return (
    <div className="filter-header" ref={rootRef}>
      <div className="filter-header-title">
        <span>{label}</span>
        <button
          ref={buttonRef}
          type="button"
          className={`set-filter-btn${isSetActive ? ' active' : ''}`}
          aria-label={`Set filter ${label}`}
          aria-expanded={open}
          aria-haspopup="dialog"
          onClick={(event) => {
            event.stopPropagation()
            if (open) { closePopover(); return }
            positionPopover() // measure the button now, in the user event
            setOpen(true)
          }}
        >
          <Filter aria-hidden="true" />
        </button>
      </div>
      <input
        ref={inputRef}
        aria-label={`Filter ${label}`}
        value={textValue}
        role="combobox"
        aria-expanded={acOpen && suggestions.length > 0}
        aria-autocomplete="list"
        onClick={(event) => event.stopPropagation()}
        onFocus={() => { positionAutocomplete(); setAcOpen(true) }}
        onChange={(event) => { props.onFilter?.(key, event.target.value); positionAutocomplete(); setAcOpen(true) }}
      />
      {acOpen && acPos && suggestions.length > 0 && createPortal(
        <ul
          ref={acRef}
          className="filter-autocomplete"
          role="listbox"
          aria-label={`${label} suggestions`}
          style={{ top: acPos.top, left: acPos.left, minWidth: acPos.width }}
          onMouseDown={(event) => event.preventDefault()}
        >
          {suggestions.map(value => (
            <li key={value} role="option" aria-selected={false}>
              <button
                type="button"
                className="filter-autocomplete-option"
                onClick={() => { props.onFilter?.(key, value); closeAutocomplete() }}
              >
                {value}
              </button>
            </li>
          ))}
        </ul>,
        document.body,
      )}
      {open && popoverPos && createPortal(
        <div
          ref={popoverRef}
          className="set-filter-popover"
          role="dialog"
          aria-label={`Set filter options for ${label}`}
          style={{ top: popoverPos.top, left: popoverPos.left }}
          onClick={(event) => event.stopPropagation()}
          onMouseDown={(event) => event.stopPropagation()}
        >
          <input
            type="search"
            className="set-filter-search"
            aria-label={`Search ${label} values`}
            placeholder="Search values…"
            value={listSearch}
            onChange={(event) => setListSearch(event.target.value)}
            onClick={(event) => event.stopPropagation()}
          />
          <div className="set-filter-actions">
            <button
              type="button"
              className="set-filter-action"
              onClick={() => props.onSetFilter?.(key, null)}
            >
              Select all
            </button>
            <button
              type="button"
              className="set-filter-action"
              onClick={() => props.onSetFilter?.(key, new Set())}
            >
              Clear
            </button>
          </div>
          <ul className="set-filter-list" role="listbox" aria-label={`${label} values`} aria-multiselectable="true">
            {filteredValues.length === 0 ? (
              <li className="set-filter-empty">No values</li>
            ) : (
              filteredValues.map(value => {
                const optionId = value === '' ? `${key}__blank__` : `${key}__${value}`
                return (
                  <li key={optionId} role="option" aria-selected={isChecked(value)}>
                    <label className="set-filter-option">
                      <input
                        type="checkbox"
                        checked={isChecked(value)}
                        onChange={() => applyToggle(value)}
                      />
                      <span>{formatFilterOptionLabel(value)}</span>
                    </label>
                  </li>
                )
              })
            )}
          </ul>
        </div>,
        document.body,
      )}
    </div>
  )
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

export function DataAdmin({ client, email, onSignOut }: Props) {
  const [kind, setKind] = useState<EntityKind>('customer')
  const [section, setSection] = useState<'entity' | 'taxonomy'>('entity')
  const [query, setQuery] = useState<QueryState>(initialQuery)
  const [filters, setFilters] = useState<Record<string, string>>({})
  const [activeFilters, setActiveFilters] = useState<Record<string, string>>({})
  const [setFiltersState, setSetFiltersState] = useState<Record<string, Set<string> | null>>({})
  const [rows, setRows] = useState<AdminRow[]>([])
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [denied, setDenied] = useState(false)
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [audit, setAudit] = useState<AuditEvent[]>([])
  const [editing, setEditing] = useState(false)
  const [editorReloadKey, setEditorReloadKey] = useState(0)
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
    setDenied(false); setRows([]); setFilters({}); setActiveFilters({}); setSetFiltersState({}); setDetail(null); setLoading(true)
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

  const updateSetFilter = useCallback((prop: string, selected: Set<string> | null) => {
    setSetFiltersState(current => ({ ...current, [prop]: selected }))
  }, [])

  const distinctValues = useMemo(() => {
    const map: Record<string, string[]> = {}
    for (const column of baseColumns) {
      const prop = String(column.prop)
      map[prop] = getDistinctColumnValues(rows, prop)
    }
    return map
  }, [rows])

  const columns = useMemo(
    () => baseColumns
      .filter(column => kind === 'customer' || column.prop !== 'plm_display')
      .map(column => ({
        ...column,
        columnTemplate: Template(FilterHeader, {
          filters,
          onFilter: updateFilter,
          setFilters: setFiltersState,
          onSetFilter: updateSetFilter,
          distinctValues,
          scope: kind,
          key: `${kind}-${String(column.prop)}`,
        }),
      })),
    [distinctValues, filters, kind, setFiltersState, updateFilter, updateSetFilter],
  )

  const visibleRows = useMemo(
    () => rows
      .filter(row => rowMatchesFilters(row, activeFilters, setFiltersState))
      .map(row => ({ ...row, plm_display: getCellDisplayValue(row, 'plm_display') })),
    [rows, activeFilters, setFiltersState],
  )

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

  // Stale-token recovery: re-fetch the record's fresh detail (new updated_at)
  // and remount the editor so the next save carries the current concurrency
  // token instead of the stale one that was loudly rejected.
  const reloadRecord = async () => {
    if (!detail) return
    await openDetail(detail as AdminRow)
    setEditorReloadKey(key => key + 1)
  }

  // Refresh grid/detail/audit but leave the MergeDialog open so its persistent
  // success receipt (audit ID + final survivor) stays visible until dismissed.
  const mergeComplete = (result: MergeResult, loserId: string) => {
    setRows(current => current.filter(row => row.id !== loserId).map(row => row.id === result.survivor?.id ? { ...row, ...result.survivor } : row))
    setDetail(current => current && result.survivor ? { ...current, ...result.survivor, name: result.survivor.display_name ?? result.survivor.name } : current)
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
    {editing && detail && <RecordEditor key={editorReloadKey} kind={kind} row={detail as AdminRow} channels={channels} onCancel={() => setEditing(false)} onSave={saveRecord} onReload={() => void reloadRecord()} />}
    {merging && detail && <MergeDialog kind={kind} survivor={detail as AdminRow} candidates={rows.filter(row => row.id !== detail.id)} onCancel={() => setMerging(false)} onPreview={loserId => previewMerge(client, kind, String(detail.id), loserId)} onMerge={(loserId, token, reason, resolutions) => executeMerge(client, kind, String(detail.id), loserId, token, reason, resolutions)} onMerged={mergeComplete} onSearchCandidates={term => searchMergeCandidates(client, kind, term, String(detail.id))} />}
    </>}
  </section>
}
