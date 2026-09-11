import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const workflow = readFileSync(fileURLToPath(new URL('../.github/workflows/documents-only-merge-authorization.yml', import.meta.url)), 'utf8')

test('documents-only authorization executes trusted base code with narrow permissions', () => {
  assert.match(workflow, /pull_request_target:/)
  assert.match(workflow, /ref: \$\{\{ github\.event\.pull_request\.base\.sha \}\}/)
  assert.doesNotMatch(workflow, /ref: \$\{\{ github\.event\.pull_request\.head/)
  assert.match(workflow, /contents: read/)
  assert.match(workflow, /pull-requests: read/)
  assert.match(workflow, /statuses: write/)
  assert.doesNotMatch(workflow, /contents: write/)
})

test('only a twice-proven prose head can receive success under the merge lock', () => {
  const classify = workflow.indexOf('name: Classify the complete pull request file list')
  const acquire = workflow.indexOf('name: Re-prove the exact head and acquire the merge/freeze lane')
  const reclassify = workflow.indexOf('name: Reclassify under the lock and post the required status')
  const success = workflow.indexOf('"$GITHUB_REPOSITORY" "$HEAD_SHA" success')
  const release = workflow.indexOf('name: Release the exclusive merge lane with ownership proof')
  assert.ok(classify >= 0 && classify < acquire && acquire < reclassify && reclassify < success && success < release)
  assert.equal(workflow.match(/check-documents-only-merge-authorization\.mjs/g)?.length, 2)
  assert.match(workflow.slice(acquire, reclassify), /--acquire-merge/)
  assert.match(workflow.slice(reclassify, success), /headRefOid/)
})

test('unknown and non-prose changes write no status while failures revoke before release', () => {
  const classify = workflow.indexOf('name: Classify the complete pull request file list')
  const acquire = workflow.indexOf('name: Re-prove the exact head and acquire the merge/freeze lane')
  const classificationStep = workflow.slice(classify, acquire)
  assert.doesNotMatch(classificationStep, /statuses\//)
  assert.doesNotMatch(classificationStep, /write-documents-only-merge-status/)
  assert.match(workflow, /if: failure\(\).*authorization\.outcome != 'success'/)
  assert.match(workflow, /if: failure\(\).*release_merge_lock\.outcome != 'success'/)
  assert.equal(workflow.match(/write-documents-only-merge-status\.mjs[\s\S]{0,160}failure/g)?.length, 2)
  assert.match(workflow, /cancel-in-progress: false/)
})
