import test from 'node:test'
import assert from 'node:assert/strict'
import { main } from './write-documents-only-merge-status.mjs'

const sha = 'a'.repeat(40)
const url = 'https://github.com/u2giants/shared-db/actions/runs/7'

test('writes the one required context through the governed transport', () => {
  let seen
  const code = main(['u2giants/shared-db', sha, 'success', 'prose verified', url], { run: (args, options) => { seen = { args, options } }, err: () => {} })
  assert.equal(code, 0)
  assert.deepEqual(seen.args, ['api', `repos/u2giants/shared-db/statuses/${sha}`, '-f', 'state=success', '-f', 'context=Migration guarded merge authorization', '-f', 'description=prose verified', '-f', `target_url=${url}`])
  assert.equal(seen.options.idempotentWrite, undefined)
})

test('invalid state, identity, head, description, or URL never reaches GitHub', () => {
  const run = () => assert.fail('transport must not run')
  for (const args of [
    ['repo', sha, 'success', 'x', url],
    ['o/r', 'abc', 'success', 'x', url],
    ['o/r', sha, 'pending', 'x', url],
    ['o/r', sha, 'success', '', url],
    ['o/r', sha, 'success', 'x', 'file:///tmp/x'],
  ]) assert.equal(main(args, { run, err: () => {} }), 2)
})

test('a transport failure is loud and returns failure without replay policy changes', () => {
  const errors = []
  const code = main(['u2giants/shared-db', sha, 'failure', 'revoked', url], { run: () => { throw new Error('HTTP 503') }, err: (text) => errors.push(text) })
  assert.equal(code, 1)
  assert.match(errors.join(''), /HTTP 503/)
})
