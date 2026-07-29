import { RevoGrid, Template, type ColumnRegular } from '@revolist/react-datagrid'
import { RefreshCw, Search } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { FilterHeader } from './FilterHeader'
import { loadLicensorTree, type ApiClient, type LoadedTree } from './lib/data-admin'
import { getDistinctColumnValues, rowMatchesFilters } from './lib/grid-filters'
import { flattenProperties, type PropertyRow } from './lib/property-rows'

type Props = { client: ApiClient }

const propertyColumns: ColumnRegular[] = [
  { prop: 'name', name: 'Property', size: 240, sortable: true },
  { prop: 'code', name: 'Code', size: 110, sortable: true },
  { prop: 'licensor_name', name: 'Licensor', size: 200, sortable: true },
  { prop: 'licensor_code', name: 'Licensor code', size: 130, sortable: true },
  { prop: 'status', name: 'Status', size: 105, sortable: true },
  { prop: 'character_count', name: 'Characters', size: 105, sortable: true },
  { prop: 'plm_display', name: 'PLM divisions', size: 260 },
  { prop: 'source_display', name: 'Source', size: 280 },
]

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

  const rows = useMemo(() => (tree ? flattenProperties(tree) : []), [tree])

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
      Read-only. DesignFlow owns the Licensor → Property relationship; this table shows the same
      records as the Licensors tree, one row per property.
    </p>

    {error && <div className="inline-error" role="alert">{error}</div>}
    {orphanCount > 0 && (
      <div className="inline-warning" role="status">
        {orphanCount} {orphanCount === 1 ? 'property has' : 'properties have'} no licensor. {orphanCount === 1 ? 'It is listed' : 'They are listed'} with “(no licensor)”.
      </div>
    )}

    <div className="grid-wrap" aria-busy={loading}>
      <RevoGrid theme="material" readonly accessible resize columns={columns} source={visibleRows} rowHeaders />
      {loading && <div className="grid-loading">Loading…</div>}
    </div>
    <footer className="grid-footer"><span>{visibleRows.length} of {rows.length} properties</span></footer>
  </section>
}
