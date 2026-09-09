// Static contract tests for the two workflows that are the ONLY sanctioned way to run the
// ColdLion history loader against the real database. They are static on purpose: the only
// dynamic test of a production writer is a production write.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const PRODUCTION_REF = "qsllyeztdwjgirsysgai";

const read = (name) =>
  readFileSync(fileURLToPath(new URL(`../.github/workflows/${name}`, import.meta.url)), "utf8");

const sync = read("coldlion-landing-sync.yml");
const backfill = read("coldlion-history-backfill.yml");
const both = [
  ["the scheduled sync", sync],
  ["the backfill", backfill],
];

test("neither workflow can be reached by a push, a pull request or a fork", () => {
  for (const [name, workflow] of both) {
    const on = workflow.slice(workflow.indexOf("\non:"), workflow.indexOf("\njobs:"));
    assert.doesNotMatch(on, /pull_request|push:/, `${name} must not run on someone else's commit`);
    assert.match(on, /workflow_dispatch/, `${name} must stay hand-startable`);
  }
});

test("every step that can write names the database it expects before it writes", () => {
  for (const [name, workflow] of both) {
    const declarations = workflow.match(/COLDLION_EXPECTED_PROJECT_REF: (\S+)/g) ?? [];
    assert.ok(declarations.length >= 2, `${name} must declare its target beside every DATABASE_URL`);
    for (const declaration of declarations) {
      assert.equal(
        declaration,
        `COLDLION_EXPECTED_PROJECT_REF: ${PRODUCTION_REF}`,
        `${name} must hard-code the target, never accept one`,
      );
    }
    assert.equal(
      (workflow.match(/DATABASE_URL: \$\{\{/g) ?? []).length,
      declarations.length,
      `${name} would otherwise carry a credential with no declared target`,
    );
  }
});

test("neither workflow can start without the secrets it needs", () => {
  for (const [name, workflow] of both) {
    assert.match(workflow, /SUPABASE_DB_URL_PRODUCTION is not set/, `${name} must fail loudly, not empty`);
    assert.match(workflow, /COLDLION_API_KEY is not set/, `${name} must fail loudly, not empty`);
  }
});

test("the offline contract tests run before anything touches the database", () => {
  for (const [name, workflow] of both) {
    const tests = workflow.indexOf("node --test tools/coldlion-landing-history.test.mjs");
    const write = workflow.search(/DATABASE_URL: \$\{\{/);
    assert.ok(tests > 0, `${name} must prove the loader still holds its contracts`);
    assert.ok(tests < write, `${name} must prove it before it is trusted with a credential`);
  }
});

test("two runs of the same loader cannot overlap", () => {
  for (const [name, workflow] of both) {
    assert.match(workflow, /concurrency:/, `${name} must serialise itself`);
    assert.match(workflow, /cancel-in-progress: false/, `${name} must never cut a window's transaction short`);
  }
});

test("no secret value can be printed", () => {
  for (const [name, workflow] of both) {
    assert.doesNotMatch(workflow, /echo .*\$\{\{\s*secrets\./, `${name} must never echo a secret`);
    assert.doesNotMatch(workflow, /echo "?\$DATABASE_URL/, `${name} must never echo the connection string`);
  }
});
