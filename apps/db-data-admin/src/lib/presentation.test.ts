import { describe, expect, it } from 'vitest'
import { formatBuildLabel, readOAuthCallbackError } from './presentation'

describe('readOAuthCallbackError', () => {
  it('reads the Supabase OAuth failure returned in the query string', () => {
    expect(readOAuthCallbackError({
      search: '?error=server_error&error_code=unexpected_failure&error_description=Unable+to+exchange+external+code%3A+1.AX',
      hash: '',
    } as Location)).toEqual({
      code: 'unexpected_failure',
      description: 'Unable to exchange external code: 1.AX',
    })
  })

  it('returns null when the callback contains no error', () => {
    expect(readOAuthCallbackError({ search: '', hash: '' } as Location)).toBeNull()
  })
})

describe('formatBuildLabel', () => {
  it('shows a short commit and readable UTC build date', () => {
    expect(formatBuildLabel('6e1b2cd902676c165eaa11201455c596169807a9', '2026-07-22'))
      .toBe('6e1b2cd · Jul 22, 2026')
  })
})
