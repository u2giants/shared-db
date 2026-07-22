export interface OAuthCallbackError {
  code: string
  description: string
}

export function readOAuthCallbackError(location: Pick<Location, 'search' | 'hash'>): OAuthCallbackError | null {
  const search = new URLSearchParams(location.search)
  const hash = new URLSearchParams(location.hash.replace(/^#/, ''))
  const code = search.get('error_code') || search.get('error') || hash.get('error_code') || hash.get('error')
  const description = search.get('error_description') || hash.get('error_description')

  if (!code && !description) return null

  return {
    code: code || 'sign_in_failed',
    description: description || 'Microsoft sign-in did not complete.',
  }
}

export function formatBuildLabel(sha: string, buildDate: string): string {
  const shortSha = sha === 'dev' || sha === 'unknown' ? sha : sha.slice(0, 7)
  if (!buildDate || buildDate === 'dev') return shortSha

  const date = new Date(`${buildDate}T00:00:00Z`)
  if (Number.isNaN(date.valueOf())) return shortSha

  return `${shortSha} · ${new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(date)}`
}
