import assert from 'node:assert/strict'
import test from 'node:test'
import {
  addedCoreCombinedTableReferences,
  allowedMigration,
} from './check-properties-and-characters-eol-references.mjs'

const diffFor = (file, added) => `diff --git a/${file} b/${file}\n--- a/${file}\n+++ b/${file}\n@@ -0,0 +1 @@\n+${added}\n`

test('rejects a new runtime dependency on the EOL combined table', () => {
  const failures = addedCoreCombinedTableReferences(
    diffFor('apps/db-data-admin/src/new-query.ts', 'select * from core.properties_and_characters'),
  )
  assert.equal(failures.length, 1)
  assert.match(failures[0], /apps\/db-data-admin/)
})

test('rejects a new migration dependency outside the exact staging migration', () => {
  const failures = addedCoreCombinedTableReferences(
    diffFor('supabase/migrations/20260828000000_new_dependency.sql', 'references core."properties_and_characters"(id)'),
  )
  assert.equal(failures.length, 1)
})

test('allows only the exact issue 1684 staging migration', () => {
  const failures = addedCoreCombinedTableReferences(
    diffFor(allowedMigration, 'comment on table core.properties_and_characters is \'EOL\';'),
  )
  assert.deepEqual(failures, [])
})

test('historical lines and test assertions are not treated as new dependencies', () => {
  const historical = `diff --git a/supabase/migrations/old.sql b/supabase/migrations/old.sql\n--- a/supabase/migrations/old.sql\n+++ b/supabase/migrations/old.sql\n context core.properties_and_characters\n`
  const testDiff = diffFor('supabase/tests/eol.sql', 'select * from core.properties_and_characters')
  assert.deepEqual(addedCoreCombinedTableReferences(historical + testDiff), [])
})
