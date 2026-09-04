#!/usr/bin/env node
// Pre-flight for the guarded merge (#1201).
//
// The guarded merge used to post its own authorization and then enter a bounded
// merge loop while holding the repository-wide exclusive merge lane. When a
// DIFFERENT required status check was missing or failing, every merge attempt was
// refused with the same "base branch policy prohibits the merge" message that the
// eventual-consistency retry exists for, so the workflow retried a condition no
// retry can resolve, held the lock for minutes, and reported nothing useful. This
// check runs BEFORE the lock is taken and names the exact contexts that are not
// satisfied on the reviewed head.
import { execFileSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { REPO } from './manage-migration-author-lanes.mjs'

export class PreflightError extends Error {}

// Posted by the guarded merge itself, after this pre-flight has passed. Requiring
// it here would make the pre-flight unsatisfiable on every first run.
export const SELF_CONTEXT = 'Migration guarded merge authorization'

const SUCCESS = new Set(['success', 'neutral', 'skipped'])

// A required context can be answered by either a commit status or a check run.
// Latest wins for each name; a check run that has not completed has no conclusion
// and is reported as pending rather than passing.
export function observedStates({ statuses = [], checkRuns = [] }) {
  const seen = new Map()
  for (const s of statuses) {
    if (!s?.context) continue
    const at = Date.parse(s.updated_at ?? s.created_at ?? 0) || 0
    const prior = seen.get(s.context)
    if (!prior || at >= prior.at) seen.set(s.context, { at, state: String(s.state ?? '') })
  }
  for (const r of checkRuns) {
    if (!r?.name) continue
    const at = Date.parse(r.completed_at ?? r.started_at ?? 0) || 0
    const state = r.status === 'completed' ? String(r.conclusion ?? '') : 'pending'
    const prior = seen.get(r.name)
    if (!prior || at >= prior.at) seen.set(r.name, { at, state })
  }
  return new Map([...seen].map(([name, v]) => [name, v.state]))
}

export function evaluatePreflight({ requiredContexts, statuses, checkRuns }) {
  if (!Array.isArray(requiredContexts)) throw new PreflightError('branch protection returned no required status check list')
  const required = requiredContexts.filter((c) => c !== SELF_CONTEXT)
  const states = observedStates({ statuses, checkRuns })
  const missing = [], pending = [], failing = []
  for (const context of required) {
    const state = states.get(context)
    if (state === undefined) missing.push(context)
    else if (SUCCESS.has(state)) continue
    else if (state === 'pending' || state === '') pending.push(`${context}`)
    else failing.push(`${context} (${state})`)
  }
  if (missing.length || pending.length || failing.length) {
    const parts = []
    if (failing.length) parts.push(`failing: ${failing.join(', ')}`)
    if (pending.length) parts.push(`still running: ${pending.join(', ')}`)
    if (missing.length) parts.push(`never reported: ${missing.join(', ')}`)
    throw new PreflightError(`required status checks are not satisfied on the reviewed head — ${parts.join('; ')}. No retry can clear this, so the merge lane was not taken.`)
  }
  return { required: required.length }
}

function gh(args) {
  // No 2>/dev/null || echo '' here: an HTTP 401/403 or a network failure must be
  // reported as itself, never as an empty result that reads like "not green yet".
  try { return execFileSync('gh', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }) }
  catch (e) { throw new PreflightError(`GitHub read failed: ${String(e.stderr || e.message).trim()}`) }
}
function json(args) { const raw = gh(args); try { return JSON.parse(raw) } catch { throw new PreflightError('GitHub returned malformed JSON') } }

export function gatherPreflightInput(env = process.env) {
  const sha = String(env.REQUESTED_SHA ?? '').trim()
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new PreflightError('REQUESTED_SHA must be a 40-character head SHA')
  let protection
  try { protection = json(['api', `repos/${REPO}/branches/main/protection/required_status_checks`]) }
  catch (e) {
    // Read access to branch protection is what makes this check possible. Say so
    // exactly, rather than degrading to a weaker test that would pass anyway.
    throw new PreflightError(`${e.message} (the workflow token needs "administration: read" to list main's required status checks)`)
  }
  const combined = json(['api', `repos/${REPO}/commits/${sha}/status?per_page=100`])
  const runs = json(['api', `repos/${REPO}/commits/${sha}/check-runs?per_page=100`])
  return { requiredContexts: protection?.contexts ?? [], statuses: combined?.statuses ?? [], checkRuns: runs?.check_runs ?? [] }
}

export function main(env = process.env) {
  try {
    const { required } = evaluatePreflight(gatherPreflightInput(env))
    console.log(`Required status checks satisfied on the reviewed head (${required} contexts).`)
    return 0
  } catch (e) { console.error(`REFUSED: ${e.message}`); return 2 }
}
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main()
