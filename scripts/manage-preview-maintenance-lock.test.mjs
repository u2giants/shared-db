import assert from 'node:assert/strict'
import test from 'node:test'
import { acquirePreviewMaintenanceLock, releasePreviewMaintenanceLock } from './manage-preview-maintenance-lock.mjs'

function io() {
  const refs = new Map()
  let counter = 0
  return {
    refs,
    mainSha: () => 'a'.repeat(40),
    getIssue: () => ({ state: 'open', body: '```db-work-scope\nstatus: ready\nwork_type: repo-maintenance\nroute: repo-maintenance\npriority: 1\ndepends_on:\nobjects:\n```' }),
    makeOwnerCommit: () => (++counter).toString(16).padStart(40, '0'),
    readRef: (ref) => refs.get(ref) ?? null,
    createRef: (ref, sha) => {
      if (refs.has(ref)) return false
      refs.set(ref, sha)
      return true
    },
    deleteRef: (ref) => refs.delete(ref),
    run: () => ({ status: 200 }),
  }
}

test('ready repository maintenance acquires and safely releases the shared preview ref', () => {
  const fake = io()
  process.env.GITHUB_RUN_ID = '123'
  process.env.GITHUB_RUN_ATTEMPT = '1'
  try {
    const lock = acquirePreviewMaintenanceLock({ issue: 771, owner: 'codex', headSha: 'a'.repeat(40) }, fake)
    assert.equal(fake.refs.get(lock.ref), lock.ownerSha)
    assert.equal(fake.refs.has('refs/db-coordination/author-acquisition'), false)
    releasePreviewMaintenanceLock(lock.ownerSha, fake)
    assert.equal(fake.refs.has(lock.ref), false)
  } finally {
    delete process.env.GITHUB_RUN_ID
    delete process.env.GITHUB_RUN_ATTEMPT
  }
})

test('wrong main, issue routing, or occupied preview fails closed', () => {
  process.env.GITHUB_RUN_ID = '123'
  process.env.GITHUB_RUN_ATTEMPT = '1'
  const stale = io()
  assert.throws(() => acquirePreviewMaintenanceLock({ issue: 771, owner: 'codex', headSha: 'b'.repeat(40) }, stale), /exact current main/)
  const wrong = io()
  wrong.getIssue = () => ({ state: 'open', body: '```db-work-scope\nstatus: blocked\nwork_type: repo-maintenance\nroute: repo-maintenance\npriority: 1\ndepends_on:\nobjects:\n```' })
  assert.throws(() => acquirePreviewMaintenanceLock({ issue: 771, owner: 'codex', headSha: 'a'.repeat(40) }, wrong), /not ready/)
  const busy = io()
  busy.refs.set('refs/db-coordination/preview', 'c'.repeat(40))
  assert.throws(() => acquirePreviewMaintenanceLock({ issue: 771, owner: 'codex', headSha: 'a'.repeat(40) }, busy), /occupied/)
  delete process.env.GITHUB_RUN_ID
  delete process.env.GITHUB_RUN_ATTEMPT
})

test('local acquisition is refused because it would be unrecoverable after a crash', () => {
  delete process.env.GITHUB_RUN_ID
  delete process.env.GITHUB_RUN_ATTEMPT
  assert.throws(() => acquirePreviewMaintenanceLock({ issue: 771, owner: 'codex', headSha: 'a'.repeat(40) }, io()), /must run in GitHub Actions/)
})
