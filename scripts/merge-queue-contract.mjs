import { execFileSync } from 'node:child_process'

export class MergeQueueError extends Error {}

export function pullRequestFromQueueRef(ref) {
  const matches = [...String(ref ?? '').matchAll(/(?:^|\/)pr-(\d+)-/g)].map(match => Number(match[1]))
  if (matches.length !== 1 || !Number.isInteger(matches[0])) {
    throw new MergeQueueError(`expected one pull request in merge-queue ref, got ${ref || '(empty)'}`)
  }
  return matches[0]
}

export function verifyQueuePullRequest(number, row) {
  if (Number(row?.number) !== Number(number)) throw new MergeQueueError(`queue ref names PR #${number}, but GitHub returned a different pull request`)
  if (row.state !== 'OPEN') throw new MergeQueueError(`queue ref names PR #${number}, but it is not open`)
  if (row.baseRefName !== 'main') throw new MergeQueueError(`queue ref names PR #${number}, but its base is not main`)
  if (!/^[0-9a-f]{40}$/i.test(String(row.headRefOid ?? ''))) throw new MergeQueueError(`queue ref names PR #${number}, but its head SHA is unreadable`)
  return Number(number)
}

export function migrationVersions(files) {
  return [...new Set(files.map(file => /^supabase\/migrations\/(\d{14})_[^/]+\.sql$/.exec(file)?.[1]).filter(Boolean))].sort()
}

export function assertOldestMigration(candidateNumber, candidateFiles, openPullRequests) {
  const candidate = migrationVersions(candidateFiles)
  if (candidate.length === 0) return { relevant: false, versions: [] }
  const blockers = []
  for (const pr of openPullRequests) {
    if (Number(pr.number) === Number(candidateNumber) || pr.isDraft) continue
    const versions = migrationVersions(pr.files ?? [])
    if (versions.length && versions[0] < candidate[0]) blockers.push({ number: Number(pr.number), version: versions[0] })
  }
  if (blockers.length) {
    blockers.sort((a, b) => a.version.localeCompare(b.version) || a.number - b.number)
    throw new MergeQueueError(`migration queue order refused: PR #${candidateNumber} starts at ${candidate[0]}, behind open PR #${blockers[0].number} at ${blockers[0].version}`)
  }
  return { relevant: true, versions: candidate }
}

export function baseNeedsPreview(paths) {
  return migrationVersions(paths).length > 0
}

function gh(args) {
  return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
}

export function readPullRequestFiles(number, run = gh) {
  const pages = JSON.parse(run(['api', '--paginate', '--slurp', `repos/u2giants/shared-db/pulls/${number}/files?per_page=100`]))
  if (!Array.isArray(pages) || pages.some(page => !Array.isArray(page))) throw new MergeQueueError(`PR #${number} file pagination is unreadable`)
  const rows = pages.flat()
  if (rows.length >= 3000) throw new MergeQueueError(`PR #${number} reaches GitHub's 3000-file coverage limit`)
  return rows.map(row => row.filename)
}

export function readOpenPullRequests(run = gh) {
  const pages = JSON.parse(run(['api', '--paginate', '--slurp', 'repos/u2giants/shared-db/pulls?state=open&per_page=100']))
  if (!Array.isArray(pages) || pages.some(page => !Array.isArray(page))) throw new MergeQueueError('open pull request pagination is unreadable')
  return pages.flat().map(row => ({ number: row.number, isDraft: Boolean(row.draft), files: readPullRequestFiles(row.number, run) }))
}

export function checkQueueOrder(number, run = gh) {
  return assertOldestMigration(number, readPullRequestFiles(number, run), readOpenPullRequests(run))
}

function main() {
  if (process.argv.includes('--resolve-queue-pr')) {
    const number = pullRequestFromQueueRef(process.env.MERGE_GROUP_REF)
    const row = JSON.parse(gh(['pr', 'view', String(number), '--repo', 'u2giants/shared-db', '--json', 'number,state,baseRefName,headRefOid']))
    console.log(verifyQueuePullRequest(number, row))
    return
  }
  const number = Number(process.env.PR_NUMBER)
  if (!Number.isInteger(number) || number < 1) throw new MergeQueueError('PR_NUMBER must be a positive integer')
  const result = checkQueueOrder(number)
  console.log(result.relevant
    ? `Migration queue order is valid: ${result.versions.join(', ')}`
    : 'No migration files changed; migration queue ordering is not applicable.')
}

if (import.meta.url === `file://${process.argv[1]?.replaceAll('\\', '/')}`) {
  try { main() } catch (error) { console.error(`REFUSED: ${error.message}`); process.exitCode = 1 }
}
