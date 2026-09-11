import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { canonicalJson } from './evidence-bundle.mjs'

export class OrchestratorSnapshotError extends Error {}
export const ORCHESTRATOR_SNAPSHOT_SCHEMA_VERSION = 1

const COLLECTIONS = Object.freeze([
  'claims', 'pull_requests', 'reviewer_leases', 'stage_locks',
  'outcome_events', 'eligible_queue',
])

const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const copy = (value) => JSON.parse(JSON.stringify(value))

function requireObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new OrchestratorSnapshotError(`${label} must be an object`)
  }
}

function stableRows(value, label) {
  if (!Array.isArray(value)) throw new OrchestratorSnapshotError(`${label} must be an array`)
  const rows = value.map((row, index) => {
    requireObject(row, `${label}[${index}]`)
    return copy(row)
  })
  return rows.sort((left, right) => canonicalJson(left).localeCompare(canonicalJson(right)))
}

export function snapshotInputs(input) {
  requireObject(input, 'snapshot input')
  requireObject(input.marker, 'marker')
  if (!Number.isInteger(input.marker.issue) || input.marker.issue <= 0) {
    throw new OrchestratorSnapshotError('marker.issue must be a positive issue number')
  }
  if (input.marker.status !== 'active' || typeof input.marker.route_id !== 'string' || !input.marker.route_id.trim()) {
    throw new OrchestratorSnapshotError('marker must be active and routable')
  }
  const normalized = { marker: copy(input.marker) }
  for (const key of COLLECTIONS) normalized[key] = stableRows(input[key], key)
  return normalized
}

export function buildOrchestratorSnapshot(input, { capturedAt } = {}) {
  const observedAt = capturedAt ?? new Date().toISOString()
  if (Number.isNaN(Date.parse(observedAt))) throw new OrchestratorSnapshotError('captured_at must be an ISO instant')
  const state = snapshotInputs(input)
  const stateDigest = sha256(canonicalJson(state))
  return {
    schema_version: ORCHESTRATOR_SNAPSHOT_SCHEMA_VERSION,
    snapshot_id: stateDigest,
    captured_at: observedAt,
    state_digest: stateDigest,
    state,
  }
}

export function verifyOrchestratorSnapshot(snapshot, currentInput) {
  requireObject(snapshot, 'snapshot')
  if (snapshot.schema_version !== ORCHESTRATOR_SNAPSHOT_SCHEMA_VERSION) {
    throw new OrchestratorSnapshotError('snapshot schema version is unsupported')
  }
  const current = snapshotInputs(currentInput)
  const currentDigest = sha256(canonicalJson(current))
  const sealedDigest = sha256(canonicalJson(snapshot.state))
  if (snapshot.snapshot_id !== snapshot.state_digest || snapshot.state_digest !== sealedDigest) {
    throw new OrchestratorSnapshotError('snapshot seal is invalid')
  }
  if (currentDigest !== snapshot.state_digest) {
    throw new OrchestratorSnapshotError(`snapshot is stale: current state digest is ${currentDigest}`)
  }
  return { status: 'CURRENT', snapshot_id: snapshot.snapshot_id }
}

export function transitionNotification(previousSnapshot, nextSnapshot) {
  requireObject(previousSnapshot, 'previous snapshot')
  requireObject(nextSnapshot, 'next snapshot')
  if (previousSnapshot.snapshot_id === nextSnapshot.snapshot_id) return null
  return {
    event_type: 'orchestrator_state_changed',
    previous_snapshot_id: previousSnapshot.snapshot_id,
    snapshot_id: nextSnapshot.snapshot_id,
  }
}

export function publishSnapshotTransition(input, { previousSnapshot = null, capturedAt, publish } = {}) {
  const snapshot = buildOrchestratorSnapshot(input, { capturedAt })
  const notification = previousSnapshot ? transitionNotification(previousSnapshot, snapshot) : {
    event_type: 'orchestrator_snapshot_created', snapshot_id: snapshot.snapshot_id,
  }
  if (notification) {
    if (typeof publish !== 'function') throw new OrchestratorSnapshotError('changed snapshot requires a publisher')
    publish({ snapshot, notification })
  }
  return { snapshot, notification }
}

export function agentCheckInNotification({ status, issue, evidence_id: evidenceId }) {
  if (['intermediate', 'unchanged', 'working', 'waiting'].includes(status)) return null
  if (!['completed', 'blocked'].includes(status)) throw new OrchestratorSnapshotError('agent check-in status is unsupported')
  if (!Number.isInteger(issue) || issue <= 0 || typeof evidenceId !== 'string' || !evidenceId.trim()) {
    throw new OrchestratorSnapshotError('terminal agent check-in requires issue and durable evidence')
  }
  return { event_type: status === 'completed' ? 'agent_completed' : 'agent_blocked', work_issue: issue, evidence_id: evidenceId }
}

export function main(argv) {
  try {
    const value = (name) => { const index=argv.indexOf(name); if(index<0||!argv[index+1])return null; return argv[index+1] }
    const inputFile=value('--input'),verifyFile=value('--verify'),previousFile=value('--previous')
    if(!inputFile)throw new OrchestratorSnapshotError('--input <json> is required')
    const input=JSON.parse(readFileSync(inputFile,'utf8'))
    if(verifyFile){console.log(JSON.stringify(verifyOrchestratorSnapshot(JSON.parse(readFileSync(verifyFile,'utf8')),input),null,2));return 0}
    const snapshot=buildOrchestratorSnapshot(input)
    const notification=previousFile?transitionNotification(JSON.parse(readFileSync(previousFile,'utf8')),snapshot):null
    console.log(JSON.stringify({snapshot,notification},null,2));return 0
  } catch(error) { console.error(`REFUSED: ${error.message}`); return 2 }
}

if(process.argv[1]&&path.resolve(fileURLToPath(import.meta.url))===path.resolve(process.argv[1]))process.exitCode=main(process.argv.slice(2))
