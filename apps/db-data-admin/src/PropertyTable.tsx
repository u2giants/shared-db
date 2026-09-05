import { RevoGrid, Template } from '@revolist/react-datagrid'
import { RefreshCw, Search } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { FilterHeader } from './FilterHeader'
import { loadLicensorTree, setPropertyStatus, type ApiClient, type LoadedTree, type PropertyStatus, type PropertyStatusResult } from './lib/data-admin'
import { getDistinctColumnValues, rowMatchesFilters } from './lib/grid-filters'
import { flattenProperties, type PropertyRow } from './lib/property-rows'
import { propertyColumns } from './property-columns'
import { PropertyStatusDialog } from './PropertyStatusDialog'

type Props = { client: ApiClient }

export function PropertyTable({ client }: Props) {
  const [tree, setTree] = useState<LoadedTree | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [denied, setDenied] = useState(false)
  const [includeInactive, setIncludeInactive] = useState(false)
  const [search, setSearch] = useState('')
  const [term, setTerm] = useState('')
  const [filters, setFilters] = useState<Record<string, string>>({})
  const [activeFilters, setActiveFilters] = useState<Record<string, string>>({})
  const [setFiltersState, setSetFiltersState] = useState<Record<string, ReadonlySet<string> | null>>({})
  const [statusTargetId, setStatusTargetId] = useState<string | null>(null)
  const [statusDialogOpen, setStatusDialogOpen] = useState(false)

  const load = useCallback(async () => {
    setLoading(true); setError(null); setDenied(false)
    try {
      setTree(await loadLicensorTree(client, { includeInactive }))
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : ''
      if (/permission|administrator|access/i.test(message)) setDenied(true)
      else setError(message || 'The Properties table could not be loaded.')
    } finally {
      setLoading(false)
    }
  }, [client, includeInactive])

  // Matches LicensorTree: `load` flips loading/error synchronously so the
  // spinner appears on the same render as the request instead of leaving stale
  // rows on screen.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load() }, [load])

  useEffect(() => {
    const handle = setTimeout(() => setTerm(search.trim().toLowerCase()), 250)
    return () => clearTimeout(handle)
  }, [search])

  // Issue #1322 decision: inactive Properties are filtered OUT by default.
  // Evidence: the tree RPC's p_include_inactive only gates LICENSOR status (its
  // where clause is `l.status <> 'inactive'`), so the server will happily keep
  // returning every property ColdLion still calls active — and the whole point
  // of the owner's paired requirement is that our own flag is what suppresses
  // lapsed licences. "Include inactive" already re-queries with
  // p_include_inactive true, so one checkbox reveals inactive licensors and
  // inactive properties together, matching the opt-in on Customers/Vendors.
  // The filtering lives here rather than in flattenProperties so the lib keeps
  // its "never drops a property" contract with the tree's reconciliation.
  const rows = useMemo(
    () => tree ? flattenProperties(tree).filter(row => includeInactive || row.status !== 'inactive') : [],
    [tree, includeInactive],
  )

  // The status target is an id, not a row copy: after a save or refresh the
  // tree reloads, and the target re-resolves to the fresh row (new updated_at)
  // instead of keeping a stale concurrency token. A row that leaves the view —
  // freshly inactive with "Include inactive" unchecked — deselects itself.
  const statusTarget = useMemo(() => rows.find(row => row.id === statusTargetId) ?? null, [rows, statusTargetId])

  // Passes the row's current updated_at through untouched: the RPC compares it
  // against the live row, and a mismatch must surface as its stale_token
  // refusal, never as a silent retry. Errors are deliberately not caught here
  // so the dialog shows the RPC's own text.
  const savePropertyStatus = useCallback(async (status: PropertyStatus, reason: string): Promise<PropertyStatusResult> => {
    if (!statusTarget) return { success: false, code: 'not_found', message: 'Select a property row first.' }
    const result = await setPropertyStatus(client, statusTarget.id, status, {
      expectedUpdatedAt: statusTarget.updated_at ?? '',
      reason,
    })
    if (result.success) void load()
    return result
  }, [client, load, statusTarget])

  const updateFilter = useCallback((prop: string, value: string) => {
    setFilters(current => ({ ...current, [prop]: value }))
    setActiveFilters(current => ({ ...current, [prop]: value }))
  }, [])

  const updateSetFilter = useCallback((prop: string, selected: Set<string> | null) => {
    setSetFiltersState(current => ({ ...current, [prop]: selected }))
  }, [])

  const distinctValues = useMemo(() => {
    const map: Record<string, string[]> = {}
    for (const column of propertyColumns) {
      const prop = String(column.prop)
      map[prop] = getDistinctColumnValues(rows, prop)
    }
    return map
  }, [rows])

  const columns = useMemo(
    () => propertyColumns.map(column => ({
      ...column,
      readonly: true,
      columnTemplate: Template(FilterHeader, {
        filters,
        onFilter: updateFilter,
        setFilters: setFiltersState,
        onSetFilter: updateSetFilter,
        distinctValues,
        scope: 'property',
        key: `property-${String(column.prop)}`,
      }),
    })),
    [distinctValues, filters, setFiltersState, updateFilter, updateSetFilter],
  )

  const visibleRows = useMemo(
    () => rows
      .filter(row => rowMatchesFilters(row, activeFilters, setFiltersState))
      .filter(row => !term || `${row.name} ${row.code ?? ''} ${row.licensor_name}`.toLowerCase().includes(term)),
    [rows, activeFilters, setFiltersState, term],
  )

  const orphanCount = useMemo(() => rows.filter((row: PropertyRow) => row.is_orphan).length, [rows])

  if (denied) return <section className="access-denied" role="alert"><h1>Access denied</h1><p>You are signed in, but DB Data Admin requires an active Administrator grant.</p></section>

  return <section className="workspace">
    <div className="controls">
      <label className="search"><Search aria-hidden="true" /><span className="sr-only">Search properties</span>
        <input placeholder="Search properties" value={search} onChange={event => setSearch(event.target.value)} />
      </label>
      <label className="check"><input type="checkbox" checked={includeInactive} onChange={event => setIncludeInactive(event.target.checked)} /> Include inactive</label>
      <button className="icon-button" aria-label="Refresh properties" onClick={() => void load()}><RefreshCw /></button>
    </div>

    <p className="muted">
      DesignFlow owns the Licensor → Property relationship; this table shows the same
      records as the Licensors tree, one row per property. Click a row to change its
      status on our side. Properties marked inactive are hidden until “Include inactive”
      is checked.
    </p>

    {statusTarget && !statusDialogOpen && <div className="property-status-target" role="status">
      <span><strong>{statusTarget.name}</strong>{statusTarget.code ? <> · {statusTarget.code}</> : null} — currently {statusTarget.status}.</span>
      <button className="secondary" onClick={() => setStatusDialogOpen(true)}>Set status…</button>
    </div>}

    {error && <div className="inline-error" role="alert">{error}</div>}
    {orphanCount > 0 && (
      <div className="inline-warning" role="status">
        {orphanCount} {orphanCount === 1 ? 'property has' : 'properties have'} no licensor. {orphanCount === 1 ? 'It is listed' : 'They are listed'} with “(no licensor)”.
      </div>
    )}

    <div className="grid-wrap" aria-busy={loading}>
      <RevoGrid
        theme="material"
        readonly
        accessible
        resize
        columns={columns}
        source={visibleRows}
        rowHeaders
        onBeforecellfocus={event => {
          const row = visibleRows[event.detail.rowIndex]
          if (row) setStatusTargetId(row.id)
        }}
      />
      {loading && <div className="grid-loading">Loading…</div>}
    </div>
    <footer className="grid-footer"><span>{visibleRows.length} of {rows.length} properties</span></footer>
    {statusDialogOpen && statusTarget && <PropertyStatusDialog
      property={statusTarget}
      onCancel={() => setStatusDialogOpen(false)}
      onSave={savePropertyStatus}
      onRefresh={() => { setStatusDialogOpen(false); void load() }}
    />}
  </section>
}
