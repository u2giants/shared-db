import { RevoGrid, Template } from '@revolist/react-datagrid'
import { RefreshCw, Search } from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import { FilterHeader } from './FilterHeader'
import { groupScrapedProperties, loadScrapedProperties, type ApiClient, type ScrapedPropertyRow } from './lib/data-admin'
import { getDistinctColumnValues, rowMatchesFilters } from './lib/grid-filters'
import { explainScrapedProperty } from './scraped-property-explanations'
import { scrapedPropertiesColumns } from './scraped-properties-columns'

type Props = { client: ApiClient }

export function ScrapedPropertiesTable({ client }: Props) {
  const [rows, setRows] = useState<ScrapedPropertyRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [denied, setDenied] = useState(false)
  const [search, setSearch] = useState('')
  const [filters, setTextFilters] = useState<Record<string, string>>({})
  const [setFilterState, setSetFilterState] = useState<Record<string, ReadonlySet<string> | null>>({})

  const load = useCallback(async () => {
    setLoading(true); setError(null); setDenied(false)
    try { setRows((await loadScrapedProperties(client)).map(row => ({ ...row, ...explainScrapedProperty(row) }))) }
    catch (cause) {
      const message = cause instanceof Error ? cause.message : (cause && typeof cause === 'object' && 'message' in cause ? String(cause.message) : '')
      if (/permission|licensing|access/i.test(message)) setDenied(true)
      else setError(message || 'Scraped Properties could not be loaded.')
    } finally { setLoading(false) }
  }, [client])

  // Matches the other read-only tables: loading state is intentionally reset
  // synchronously when this mounted view begins its request.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void load() }, [load])

  const distinctValues = useMemo(() => Object.fromEntries(scrapedPropertiesColumns.map(column => {
    const prop = String(column.prop)
    return [prop, getDistinctColumnValues(rows, prop)]
  })), [rows])

  const gridColumns = useMemo(() => scrapedPropertiesColumns.map(column => ({
    ...column,
    readonly: true,
    columnTemplate: Template(FilterHeader, {
      filters,
      onFilter: (prop: string, value: string) => setTextFilters(current => ({ ...current, [prop]: value })),
      setFilters: setFilterState,
      onSetFilter: (prop: string, selected: Set<string> | null) => setSetFilterState(current => ({ ...current, [prop]: selected })),
      distinctValues,
      scope: 'scraped-properties',
      key: `scraped-properties-${String(column.prop)}`,
    }),
  })), [distinctValues, filters, setFilterState])

  const visibleRows = useMemo(() => {
    const term = search.trim().toLowerCase()
    return rows.filter(row => rowMatchesFilters(row, filters, setFilterState)).filter(row =>
      !term || `${row.display_label} ${row.presentation_licensor_name} ${row.source_system} ${row.source_property_id} ${row.provenance_kind} ${row.review_reason} ${row.evidence_basis} ${row.review_guidance}`.toLowerCase().includes(term),
    )
  }, [filters, rows, search, setFilterState])
  const groups = useMemo(() => groupScrapedProperties(visibleRows), [visibleRows])

  if (denied) return <section className="access-denied" role="alert"><h1>Access denied</h1><p>This read-only screen requires an active Licensing Manager grant.</p></section>

  return <section className="workspace scraped-properties">
    <div className="controls">
      <label className="search"><Search aria-hidden="true" /><span className="sr-only">Search scraped properties</span><input placeholder="Search scraped properties" value={search} onChange={event => setSearch(event.target.value)} /></label>
      <button className="icon-button" aria-label="Refresh scraped properties" onClick={() => void load()}><RefreshCw /></button>
    </div>
    <p className="muted">Read-only source-declared Property vocabularies retained from authorized licensor scrapes. Presentation Licensor and source provenance remain separate.</p>
    {error && <div className="inline-error" role="alert">{error}</div>}
    <div aria-busy={loading}>
      {groups.map(group => <section key={group.key} className="scraped-property-group" aria-labelledby={`scraped-${group.key}`}>
        <h2 id={`scraped-${group.key}`}>{group.name}</h2>
        <p className="muted">{group.rows.length} {group.rows.length === 1 ? 'property' : 'properties'}</p>
        {group.rows.some(row => /conflict|unresolved|ambiguous_crossover/i.test(row.source_status ?? '')) && <div role="note" aria-label={`${group.name} review details`}>
          {[...new Map(group.rows.filter(row => /conflict|unresolved|ambiguous_crossover/i.test(row.source_status ?? '')).map(row => [
            `${row.review_reason}|${row.evidence_basis}|${row.review_guidance}`,
            row,
          ])).values()].map(row => <p key={`${row.review_reason}|${row.evidence_basis}|${row.review_guidance}`} className="muted" title={`Authority review detail: ${row.review_reason} Evidence basis: ${row.evidence_basis}. Decision guidance: ${row.review_guidance}`}>
            <strong>{row.review_reason}</strong> Evidence basis: {row.evidence_basis}. {row.review_guidance}
          </p>)}
        </div>}
        <div className="grid-wrap"><RevoGrid theme="material" readonly accessible resize columns={gridColumns} source={group.rows} rowHeaders /></div>
      </section>)}
      {loading && <div className="grid-loading">Loading…</div>}
    </div>
    <footer className="grid-footer"><span>{visibleRows.length} of {rows.length} scraped properties</span></footer>
  </section>
}
