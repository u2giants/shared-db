import { describe, expect, it, vi } from 'vitest'
import { initialQuery, loadAllRows, toRpcParams } from './data-admin'

describe('DB Data Admin query contracts', () => {
  it('maps the customer-only channel without changing the vendor signature', () => {
    expect(toRpcParams('customer', { ...initialQuery, channelId: 'channel-1' })).toMatchObject({ p_channel_id: 'channel-1', p_page_size: 200 })
    expect(toRpcParams('vendor', initialQuery)).not.toHaveProperty('p_channel_id')
  })

  it('loads client-side pages until the cursor is exhausted', async () => {
    const rpc = vi.fn()
      .mockResolvedValueOnce({ data: { rows: [{ id: '1' }], next_cursor: 'next' }, error: null })
      .mockResolvedValueOnce({ data: { rows: [{ id: '2' }], next_cursor: null }, error: null })
    const result = await loadAllRows({ rpc } as never, 'customer', initialQuery)
    expect(result.rows.map(row => row.id)).toEqual(['1', '2'])
    expect(rpc).toHaveBeenCalledTimes(2)
  })
})
