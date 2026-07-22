import { expect, test, type Page, type Route } from '@playwright/test'

const customers = [
  { id: '11111111-1111-1111-1111-111111111111', display_name: 'Acme Retail', status: 'active', crm_status: 'active', pm_status: 'active', dam_status: 'inactive', plm_status: 'ACTIVE', erp_active: true, alias_count: 2, updated_at: '2026-07-22T12:00:00Z' },
  { id: '22222222-2222-2222-2222-222222222222', display_name: 'Northwind Stores', status: 'active', crm_status: 'active', pm_status: 'inactive', dam_status: 'active', plm_status: null, erp_active: true, alias_count: 1, updated_at: '2026-07-21T12:00:00Z' },
]
const vendors = [{ id: '33333333-3333-3333-3333-333333333333', display_name: 'Atlas Manufacturing', status: 'active', crm_status: 'active', pm_status: 'active', dam_status: 'active', plm_status: null, erp_active: true, alias_count: 3, updated_at: '2026-07-20T12:00:00Z' }]

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
    if (name.endsWith('_detail')) return route.fulfill({ json: { id: body?.p_id, aliases: [{ alias: 'Legacy name', source_system: 'ERP' }], source_refs: [{ source_system: 'Coldlion', source_id: 'C-100' }] } })
    if (name === 'db_data_admin_customer_list') return route.fulfill({ json: { rows: customers, next_cursor: null, page_size: 200 } })
    if (name === 'db_data_admin_vendor_list') return route.fulfill({ json: { rows: vendors, next_cursor: null, page_size: 200 } })
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

test('keeps the admin grid usable at a narrow viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 }); await mockAdmin(page); await page.goto('/')
  await expect(page.locator('revo-grid')).toBeVisible()
  await expect(page.getByText('Acme Retail')).toBeVisible()
  await page.screenshot({ path: '../../docs/verification/db-data-admin-step7-narrow.png', fullPage: true })
})
