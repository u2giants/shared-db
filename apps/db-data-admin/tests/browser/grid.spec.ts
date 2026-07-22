import { expect, test, type Page, type Route } from '@playwright/test'

const customers = [
  { id: '11111111-1111-1111-1111-111111111111', display_name: 'Acme Retail', status: 'active', crm_status: 'active', pm_status: 'active', dam_status: 'inactive', plm_status: 'ACTIVE', erp_active: true, alias_count: 2, updated_at: '2026-07-22T12:00:00Z' },
  { id: '22222222-2222-2222-2222-222222222222', display_name: 'Northwind Stores', status: 'active', crm_status: 'active', pm_status: 'inactive', dam_status: 'active', plm_status: null, erp_active: true, alias_count: 1, updated_at: '2026-07-21T12:00:00Z' },
]
const vendors = [{ id: '33333333-3333-3333-3333-333333333333', display_name: 'Atlas Manufacturing', status: 'active', crm_status: 'active', pm_status: 'active', dam_status: 'active', plm_status: null, erp_active: true, alias_count: 3, updated_at: '2026-07-20T12:00:00Z' }]

// Step 10 read-only Licensor -> Property tree fixture. The collide property
// carries mg_code "DNY" (Disney's code) but is parented to Marvel by its
// canonical licensor_id, proving the edge never comes from mg_code.
const licensorTree = {
  snapshot: { snapshot_at: '2026-07-22T12:00:00Z', store: 'core.licensor / core.property (Supabase canonical mirror)', source_system: 'designflow_plm', feeder_last_sync_at: '2026-07-08T03:30:00Z', feeder_last_run_status: 'succeeded', feeder_days_stale: 14, feeder_available: false, live_upstream_reconciliation: false, note: 'Snapshot of the canonical Supabase mirror. The edge is DesignFlow-owned and mirrored via core.property.licensor_id; never inferred from mgTypeCode or mg_code.' },
  reconciliation: { licensor_count: 3, active_licensor_count: 3, property_count: 4, active_property_count: 4, properties_with_licensor: 3, orphan_property_count: 1, expected_orphan_count_is_zero: false, partition_reconciles: true },
  licensors: [
    { id: '44444444-0001-4000-8000-000000000001', name: 'Marvel', code: 'MRV', status: 'active', property_count: 2, updated_at: '2026-07-22T10:00:00Z', source_refs: [{ source_system: 'designflow_plm', source_table: 'merchGroup', source_id: 'mg-mrv', source_code: 'MRV', source_name: 'Marvel' }], plm_context: [{ plm_id: 'li-cw', division_code: 'CW001', mg_code: 'MRV', mg_type: 'licensor', mg_category: 'licensed' }, { plm_id: 'li-sp', division_code: 'SP001', mg_code: 'MRV', mg_type: 'licensor', mg_category: 'licensed' }], properties: [
      { id: '44444444-0002-4000-8000-000000000002', name: 'Avengers', code: 'AVG', status: 'active', character_count: 6, source_refs: [{ source_system: 'designflow_plm', source_table: 'merchGroup', source_id: 'mg-avg', source_code: 'AVG', source_name: 'Avengers' }], plm_context: [{ plm_id: 'pr-avg', division_code: 'CW001', mg_code: 'AVG', mg_type: 'property', mg_category: 'licensed' }] },
      { id: '44444444-0003-4000-8000-000000000003', name: 'Spider-Man', code: 'SPD', status: 'active', character_count: 2, source_refs: [], plm_context: [{ plm_id: 'pr-spd', division_code: 'CW001', mg_code: 'DNY', mg_type: 'property', mg_category: 'licensed' }] },
    ] },
    { id: '44444444-0004-4000-8000-000000000004', name: 'Disney', code: 'DNY', status: 'active', property_count: 1, updated_at: '2026-07-22T10:00:00Z', source_refs: [], plm_context: [{ plm_id: 'li-dny', division_code: 'CW001', mg_code: 'DNY', mg_type: 'licensor', mg_category: 'licensed' }], properties: [
      { id: '44444444-0005-4000-8000-000000000005', name: 'Frozen', code: 'FRZ', status: 'active', character_count: 0, source_refs: [], plm_context: [{ plm_id: 'pr-frz', division_code: 'CW001', mg_code: 'FRZ', mg_type: 'property', mg_category: 'licensed' }] },
    ] },
    { id: '44444444-0006-4000-8000-000000000006', name: 'Warner Bros', code: 'WB', status: 'inactive', property_count: 0, updated_at: '2026-07-22T10:00:00Z', source_refs: [], plm_context: [], properties: [] },
  ],
  orphan_properties: [
    { id: '44444444-0007-4000-8000-000000000007', name: 'Unassigned IP', code: 'UNA', status: 'active', licensor_id: null, character_count: 0, source_refs: [], plm_context: [] },
  ],
  next_cursor: null, page_size: 200,
}

async function mockAdmin(page: Page) {
  await page.addInitScript(() => localStorage.setItem('sb-preview-auth-token', JSON.stringify({ access_token: 'mock-token', refresh_token: 'mock-refresh', expires_at: 4102444800, expires_in: 3600, token_type: 'bearer', user: { id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', email: 'albert@popcre.com', aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: '2026-07-22T00:00:00Z' } })))
  await page.route('**/config.js', route => route.fulfill({ contentType: 'application/javascript', body: "window.__DB_DATA_ADMIN_CONFIG__={supabaseUrl:'https://preview.supabase.co',supabaseAnonKey:'mock-anon',authRedirectUrl:'http://127.0.0.1:4173'}" }))
  await page.route('https://preview.supabase.co/rest/v1/rpc/**', async (route: Route) => {
    const name = route.request().url().split('/').pop() ?? ''
    const body = route.request().postDataJSON() as Record<string, unknown> | null
    if (name === 'db_data_admin_channel_list') return route.fulfill({ json: [{ id: 'mass', name: 'Mass' }] })
    if (name === 'db_data_admin_grid_state_get') return route.fulfill({ json: null })
    if (name === 'db_data_admin_grid_state_upsert') return route.fulfill({ json: { version: 1 } })
    if (name === 'db_data_admin_audit_list') return route.fulfill({ json: { rows: [{ id: 'audit-1', action: 'update', reason: 'Curated correction', actor_label: 'Albert', occurred_at: '2026-07-22T12:30:00Z', succeeded: true }], next_cursor: null } })
    if (name === 'db_data_admin_update_customer') return route.fulfill({ json: { success: true, audit_id: 'audit-1', row: { ...customers[0], display_name: 'Acme Retail Group' } } })
    if (name === 'db_data_admin_update_vendor') return route.fulfill({ json: { success: true, audit_id: 'audit-2', row: vendors[0] } })
    if (name === 'db_data_admin_preview_customer_merge') return route.fulfill({ json: { success: true, preview_token: 'preview-token', preview: { entity_type: 'customer', survivor: customers[0], loser: customers[1], affected_counts: { 'core.company_source_ref.company_id': 3, 'crm.department.company_id': 2 }, conflicts: [{ key: 'crm.status', app: 'crm', field: 'status', survivor: 'active', loser: 'inactive' }], moving_aliases: [{ alias: 'Northwind Retail Co', alias_type: 'legacy', source_system: 'coldlion', origin: 'existing_alias' }, { alias: 'Northwind Stores', alias_type: 'merged_name', source_system: 'db_data_admin_merge', origin: 'loser_name' }], moving_source_refs: [{ source_system: 'coldlion', source_table: 'customers', source_id: 'C-201', source_code: 'NW-201', source_name: 'Northwind' }] } } })
    if (name === 'db_data_admin_merge_customer') return route.fulfill({ json: { success: true, audit_id: 'audit-merge', survivor: customers[0] } })
    if (name.endsWith('_detail')) return route.fulfill({ json: { id: body?.p_id, aliases: [{ alias: 'Legacy name', source_system: 'ERP' }], source_refs: [{ source_system: 'Coldlion', source_id: 'C-100' }] } })
    if (name === 'db_data_admin_customer_list') return route.fulfill({ json: { rows: customers, next_cursor: null, page_size: 200 } })
    if (name === 'db_data_admin_vendor_list') return route.fulfill({ json: { rows: vendors, next_cursor: null, page_size: 200 } })
    if (name === 'db_data_admin_licensor_property_tree') return route.fulfill({ json: licensorTree })
    return route.fulfill({ json: {} })
  })
}

test('renders persistent customer and vendor grids with lazy details', async ({ page }) => {
  await mockAdmin(page); await page.goto('/')
  await expect(page.getByRole('button', { name: 'Customers' })).toHaveClass(/active/)
  await expect(page.locator('revo-grid')).toBeVisible()
  await expect(page.getByText('Acme Retail')).toBeVisible()
  await page.getByText('Acme Retail').click()
  await expect(page.getByRole('complementary', { name: 'customer details' })).toContainText('Legacy name')
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step8-detail-audit.png', fullPage: true })
  await page.getByRole('button', { name: 'Edit record' }).click()
  await expect(page.getByRole('dialog', { name: 'Edit Customer' })).toBeVisible()
  await page.getByLabel('Curated display name').fill('Acme Retail Group')
  await page.getByLabel('Reason').fill('Curated correction')
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step8-editor.png', fullPage: true })
  await page.getByRole('button', { name: 'Save change' }).click()
  await expect(page.getByRole('status')).toContainText('Saved and audited')
  await page.getByRole('button', { name: 'Close editor' }).click()
  await page.getByRole('button', { name: 'Close details' }).click()
  const filter = page.getByRole('textbox', { name: 'Filter Name' })
  await filter.fill('Acme'); await page.waitForTimeout(350)
  await expect(filter).toBeFocused(); await expect(filter).toHaveValue('Acme')
  await page.getByRole('button', { name: 'Vendors' }).click()
  await expect(page.getByRole('button', { name: 'Vendors' })).toHaveClass(/active/)
  await expect(page.getByText('Atlas Manufacturing')).toBeVisible()
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step7-vendor-wide.png', fullPage: true })
})

test('previews and explicitly confirms a protected duplicate merge', async ({ page }) => {
  // The corrected preview contains the complete moving-detail contract. Use a
  // tall evidence viewport so the screenshot captures the dialog from its
  // title through confirmation without recording an internally scrolled state.
  await page.setViewportSize({ width: 1280, height: 1400 })
  await mockAdmin(page); await page.goto('/')
  await page.getByText('Acme Retail').click()
  await page.getByRole('button', { name: 'Merge duplicate' }).click()
  await page.getByLabel('Duplicate to absorb').selectOption(customers[1].id)
  await expect(page.getByText('Resolve every conflict')).toBeVisible()
  await expect(page.getByText('core.company_source_ref.company_id')).toBeVisible()
  // Step 9 correction: the preview must show the exact aliases and source
  // references that will move, not only affected counts.
  await expect(page.getByText('Aliases that will move to the survivor')).toBeVisible()
  await expect(page.getByText('Northwind Retail Co')).toBeVisible()
  await expect(page.getByText("duplicate's current name")).toBeVisible()
  await expect(page.getByText('Source references that will move to the survivor')).toBeVisible()
  await expect(page.getByText('coldlion/customers')).toBeVisible()
  await page.getByLabel('Keep: active').check()
  await page.getByPlaceholder(/permanent audit/i).fill('Confirmed duplicate company')
  await page.getByLabel(/I confirm/).check()
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step9-moving-detail-preview.png', fullPage: true })
  await page.getByRole('button', { name: 'Merge records' }).click()
  // Step 9 correction: an accessible success receipt with the final survivor and
  // audit/operation ID persists until dismissed.
  await expect(page.getByRole('heading', { name: 'Merge complete' })).toBeVisible()
  const receipt = page.getByRole('status').filter({ hasText: 'was absorbed' })
  await expect(receipt).toBeVisible()
  await expect(page.getByText('audit-merge')).toBeVisible()
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step9-merge-receipt.png', fullPage: true })
  await page.getByRole('button', { name: 'Done' }).click()
  await expect(page.getByRole('gridcell', { name: 'Northwind Stores' })).not.toBeVisible()
})

test('surfaces a stale concurrency-token save failure and recovers after reloading the record', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 1000 })
  await mockAdmin(page)
  // The first save races a concurrent edit and is loudly rejected as stale; the
  // second save (after the editor reloads fresh data) succeeds. Registered after
  // mockAdmin so this exact-URL route takes precedence over its catch-all.
  let updateAttempts = 0
  await page.route('https://preview.supabase.co/rest/v1/rpc/db_data_admin_update_customer', async (route: Route) => {
    updateAttempts += 1
    if (updateAttempts === 1) return route.fulfill({ json: { success: false, code: 'stale_token', current: { ...customers[0], updated_at: '2026-07-22T13:00:00Z' } } })
    return route.fulfill({ json: { success: true, audit_id: 'audit-recovered', row: { ...customers[0], display_name: 'Acme Retail Group' } } })
  })
  await page.goto('/')
  await page.getByText('Acme Retail').click()
  await page.getByRole('button', { name: 'Edit record' }).click()
  await page.getByLabel('Curated display name').fill('Acme Retail Group')
  await page.getByLabel('Reason').fill('Curated correction')
  await page.getByRole('button', { name: 'Save change' }).click()
  // Loud, accessible failure — never a silent overwrite.
  await expect(page.getByRole('alert')).toContainText('changed elsewhere')
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step8-stale-token.png', fullPage: true })
  // One-click recovery: reload re-fetches the record and remounts the editor.
  await page.getByRole('button', { name: 'Reload record' }).click()
  await expect(page.getByRole('dialog', { name: 'Edit Customer' })).toBeVisible()
  await page.getByLabel('Curated display name').fill('Acme Retail Group')
  await page.getByLabel('Reason').fill('Curated correction after reload')
  await page.getByRole('button', { name: 'Save change' }).click()
  await expect(page.getByRole('status')).toContainText('Saved and audited')
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step8-stale-token-recovered.png', fullPage: true })
})

test('keeps the admin grid usable at a narrow viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 }); await mockAdmin(page); await page.goto('/')
  await expect(page.locator('revo-grid')).toBeVisible()
  await expect(page.getByText('Acme Retail')).toBeVisible()
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step7-narrow.png', fullPage: true })
})

test('renders the read-only Licensor -> Property tree with counts, source context, and a loud orphan', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 1000 })
  await mockAdmin(page); await page.goto('/')
  await page.getByRole('button', { name: 'Licensors' }).click()
  await page.getByLabel('Include inactive').check()
  await expect(page.getByText('3 licensors')).toBeVisible()
  await expect(page.getByText('4 properties')).toBeVisible()
  await expect(page.getByText(/upstream feeder unavailable/i)).toBeVisible()
  // Orphan surfaced loudly and separately.
  await expect(page.getByRole('alert').filter({ hasText: 'Unassigned IP' })).toBeVisible()
  // Expand a licensor to reveal a property; Spider-Man (mg_code DNY) nests
  // under Marvel, not Disney.
  await page.getByRole('button', { name: /expand licensor marvel/i }).click()
  await expect(page.getByText('Spider-Man')).toBeVisible()
  await expect(page.locator('[aria-label="Properties of Marvel"]')).toContainText('Spider-Man')
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step10-licensor-tree.png', fullPage: true })
})
