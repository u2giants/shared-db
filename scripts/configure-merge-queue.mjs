import { execFileSync } from 'node:child_process'

export const RULESET_NAME = 'main merge queue'
export const QUEUE_RULE = {
  type: 'merge_queue',
  parameters: {
    check_response_timeout_minutes: 30,
    grouping_strategy: 'ALLGREEN',
    max_entries_to_build: 1,
    max_entries_to_merge: 1,
    merge_method: 'MERGE',
    min_entries_to_merge: 1,
    min_entries_to_merge_wait_minutes: 0,
  },
}

export function desiredRuleset() {
  return {
    name: RULESET_NAME,
    target: 'branch',
    enforcement: 'active',
    conditions: { ref_name: { include: ['refs/heads/main'], exclude: [] } },
    rules: [QUEUE_RULE],
  }
}

export function assertActivationReady({ rulesets, contexts, workflows }) {
  if (!Array.isArray(rulesets) || !Array.isArray(contexts) || !Array.isArray(workflows)) throw new Error('live GitHub state is unreadable')
  const sameName = rulesets.filter(row => row.name === RULESET_NAME)
  if (sameName.length > 1) throw new Error(`multiple rulesets named ${RULESET_NAME}`)
  for (const required of ['Migration guarded merge authorization', 'Merge queue gate']) {
    if (!contexts.includes(required)) throw new Error(`required context is not active: ${required}`)
  }
  if (!workflows.includes('merge-queue-gate.yml')) throw new Error('merge-queue-gate.yml is not present on main')
  return sameName[0] ?? null
}

function gh(args, options = {}) {
  return execFileSync('gh', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...options })
}

function main() {
  const apply = process.argv.includes('--apply')
  const rulesets = JSON.parse(gh(['api', 'repos/u2giants/shared-db/rulesets']))
  const protection = JSON.parse(gh(['api', 'repos/u2giants/shared-db/branches/main/protection']))
  const tree = JSON.parse(gh(['api', 'repos/u2giants/shared-db/contents/.github/workflows?ref=main'])).map(row => row.name)
  const existing = assertActivationReady({ rulesets, contexts: protection.required_status_checks?.contexts ?? [], workflows: tree })
  const desired = desiredRuleset()
  console.log(JSON.stringify({ mode: apply ? 'APPLY' : 'DRY RUN', existing, desired }, null, 2))
  if (!apply) return
  const body = JSON.stringify(desired)
  const result = existing
    ? gh(['api', '--method', 'PUT', `repos/u2giants/shared-db/rulesets/${existing.id}`, '--input', '-'], { input: body })
    : gh(['api', '--method', 'POST', 'repos/u2giants/shared-db/rulesets', '--input', '-'], { input: body })
  const written = JSON.parse(result)
  if (written.name !== RULESET_NAME || written.enforcement !== 'active') throw new Error('merge queue ruleset write did not read back active')
  console.log(`ACTIVATED ruleset ${written.id}: ${written._links?.html?.href ?? '(no URL)'}`)
}

if (import.meta.url === `file://${process.argv[1]?.replaceAll('\\', '/')}`) {
  try { main() } catch (error) { console.error(`REFUSED: ${error.message}`); process.exitCode = 2 }
}
