// Backlog B14 — the cycle-state probe must not return the whole ColdLion mirror as one
// buffered document, and a CLIENT-SIDE tooling fault must not be recorded as a sync failure.
//
// WHY BOTH HALVES ARE HERE
// ------------------------
// PR #362 raised the spawnSync `maxBuffer` from Node's 1 MiB default to 256 MiB after the real
// probe returned 1,305,075 bytes on preview. That moved the cliff without removing it: an
// overflow still threw, still landed in the runner's catch, still wrote a durable failed
// `ingest.sync_run` row, and two consecutive failed rows still auto-trip the
// coldlion_licensor_property circuit breaker. Identical blast radius, better message.
//
//   Half 1 — tools/promote-coldlion-source-owned.mjs pages the probe, so the payload is bounded
//            by CYCLE_STATE_PAGE_SIZE instead of by the size of the mirror.
//   Half 2 — tools/coldlion-sync-common.mjs tags a spawn-level fault CLIENT_SPAWN_FAULT, and the
//            runner exits 4 for it WITHOUT recording a durable failure or an alert.
//
// FULLY OFFLINE. No database and no network. The paging tests inject a fake runSql. The
// breaker tests drive the REAL `main()` across the REAL spawn boundary, with PATH pointed
// either at an empty directory (genuine ENOENT) or at a fake `supabase` executable that is a
// copy of this Node binary driven by a NODE_OPTIONS preload — the same stub pattern as
// tools/coldlion-sync-common-runsql.test.mjs.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  CYCLE_STATE_PAGE_SIZE,
  EXIT_CLIENT_TOOLING_FAULT,
  EXIT_SKIPPED_ALREADY_RUNNING,
  buildCycleStateSql,
  main,
  readCycleState,
} from "./promote-coldlion-source-owned.mjs";
import { CLIENT_SPAWN_FAULT_CODE, isClientSpawnFault } from "./coldlion-sync-common.mjs";

// =======================================================================================
// Half 1 — the probe is paged
// =======================================================================================

test("the probe SQL always carries an explicit bounded window", () => {
  const sql = buildCycleStateSql();
  assert.match(sql, /offset 0 limit 1000/, "the default page must be an explicit offset/limit");
  assert.match(sql, /'page_offset', 0::bigint/);
  assert.match(sql, /'page_limit', 1000::bigint/);
  // The window has to sit on the mirror union, BEFORE the joins, or a page would still make
  // the database materialise every row.
  const windowAt = sql.indexOf("offset 0 limit 1000");
  assert.ok(windowAt > 0 && windowAt < sql.indexOf("left join lateral"));
});

test("the probe SQL is parameterised by page, not fixed at page one", () => {
  const sql = buildCycleStateSql({ offset: 3000, limit: 500 });
  assert.match(sql, /offset 3000 limit 500/);
  assert.doesNotMatch(sql, /offset 0 limit/);
});

test("the probe refuses a nonsensical window instead of emitting broken SQL", () => {
  assert.throws(() => buildCycleStateSql({ offset: -1 }), /invalid probe offset/);
  assert.throws(() => buildCycleStateSql({ offset: 1.5 }), /invalid probe offset/);
  assert.throws(() => buildCycleStateSql({ limit: 0 }), /invalid probe limit/);
  assert.throws(() => buildCycleStateSql({ limit: "1000" }), /invalid probe limit/);
});

test("CYCLE_STATE_PAGE_SIZE keeps a page far below Node's 1 MiB DEFAULT maxBuffer", () => {
  // ~700 bytes of JSON per row against the 1 MiB default: the page must fit even if the
  // raised maxBuffer were removed entirely. This is what makes the ceiling a second line of
  // defence rather than the only one.
  assert.ok(CYCLE_STATE_PAGE_SIZE * 700 < 1024 * 1024, "a full page must fit in 1 MiB");
});

/** Build the exact stdout shape `supabase db query --output json` returns for the probe. */
function pageStdout({ snapshot = "run-1", rows = [] }) {
  return JSON.stringify([{ jsonb_build_object: { ok: true, snapshot_run_id: snapshot, rows } }]);
}

function row(n, over = {}) {
  return {
    entityType: "property",
    company: "01",
    division: "D1",
    mgTypeCode: "T",
    mgCode: `MG${String(n).padStart(4, "0")}`,
    name: `Prop ${n}`,
    resolution_status: "manually_matched",
    present_this_cycle: true,
    ...over,
  };
}

test("readCycleState stitches successive bounded pages into the whole cycle", () => {
  const seen = [];
  const pages = [[row(1), row(2)], [row(3), row(4)], [row(5)]];
  const runSqlImpl = (sql) => {
    const m = /offset (\d+) limit (\d+)/.exec(sql);
    seen.push([Number(m[1]), Number(m[2])]);
    return pageStdout({ rows: pages[seen.length - 1] ?? [] });
  };

  const cycle = readCycleState({ linked: true, pageSize: 2, runSqlImpl });

  assert.deepEqual(seen, [[0, 2], [2, 2], [4, 2]], "each page must advance by exactly pageSize");
  assert.equal(cycle.pages_fetched, 3);
  assert.equal(cycle.rows.length, 5, "no row may be lost or duplicated in the stitch");
  assert.deepEqual(
    cycle.rows.map((r) => r.mgCode),
    ["MG0001", "MG0002", "MG0003", "MG0004", "MG0005"],
    "the pages must be concatenated in order",
  );
  assert.equal(cycle.snapshot_run_id, "run-1");
  assert.equal(cycle.ok, true);
});

test("readCycleState stops on the first SHORT page and asks for nothing more", () => {
  let calls = 0;
  const cycle = readCycleState({
    pageSize: 10,
    runSqlImpl: () => {
      calls += 1;
      return pageStdout({ rows: [row(1), row(2)] });
    },
  });
  assert.equal(calls, 1, "a short page ends the read; a second call is a wasted round trip");
  assert.equal(cycle.rows.length, 2);
});

test("readCycleState FAILS CLOSED if the mirror snapshot changes between pages", () => {
  let calls = 0;
  assert.throws(
    () =>
      readCycleState({
        pageSize: 2,
        runSqlImpl: () => {
          calls += 1;
          return pageStdout({
            snapshot: calls === 1 ? "run-1" : "run-2",
            rows: [row(calls * 10), row(calls * 10 + 1)],
          });
        },
      }),
    /snapshot changed between cycle-state pages/,
    "two pages from two different cycles must never be promoted as one",
  );
});

test("readCycleState FAILS CLOSED if the ordered window shifts and repeats a row", () => {
  // A duplicate is the observable symptom of a shifted window — and a shifted window means
  // some OTHER row was skipped entirely, which the planner would read as a record ColdLion
  // stopped sending. Silently promoting that is the dangerous direction.
  let calls = 0;
  assert.throws(
    () =>
      readCycleState({
        pageSize: 2,
        runSqlImpl: () => {
          calls += 1;
          return pageStdout({ rows: calls === 1 ? [row(1), row(2)] : [row(2), row(3)] });
        },
      }),
    /twice; the ordered window shifted/,
  );
});

test("readCycleState returns null (exit 2, unparseable) rather than throwing", () => {
  assert.equal(readCycleState({ runSqlImpl: () => "not json at all" }), null);
});

test("readCycleState refuses to loop forever on endlessly full pages", () => {
  let calls = 0;
  assert.throws(
    () =>
      readCycleState({
        pageSize: 1,
        runSqlImpl: () => {
          calls += 1;
          return pageStdout({ rows: [row(calls)] });
        },
      }),
    /refusing to loop/,
  );
});

// =======================================================================================
// Half 2 — a client-side tooling fault can NEVER trip the circuit breaker
// =======================================================================================

const PRELOAD = `
const fs = require("node:fs");
const argv = process.argv.slice(1);
const fileIdx = argv.indexOf("--file");
const sql = fileIdx >= 0 ? fs.readFileSync(argv[fileIdx + 1], "utf8") : "";
fs.appendFileSync(process.env.FAKE_SUPABASE_LOG, JSON.stringify({ argv, sql }) + "\\n");
fs.writeSync(2, "ERROR:  simulated database failure\\n");
process.exit(1);
`;

let stubDir = null;
let emptyDir = null;
let logFile = null;
const SAVED = {};

before(() => {
  stubDir = mkdtempSync(join(tmpdir(), "b14-stub-"));
  emptyDir = mkdtempSync(join(tmpdir(), "b14-empty-"));
  logFile = join(stubDir, "calls.log");
  const preloadPath = join(stubDir, "preload.cjs");
  writeFileSync(preloadPath, PRELOAD, "utf8");
  const exe = join(stubDir, process.platform === "win32" ? "supabase.exe" : "supabase");
  try {
    if (process.platform === "win32") copyFileSync(process.execPath, exe);
    else symlinkSync(process.execPath, exe);
  } catch {
    copyFileSync(process.execPath, exe);
  }
  for (const n of ["PATH", "Path", "NODE_OPTIONS", "DATABASE_URL", "SUPABASE_DB_URL", "FAKE_SUPABASE_LOG"]) {
    SAVED[n] = process.env[n];
  }
  process.env.NODE_OPTIONS = `--require "${preloadPath.replace(/\\/g, "/")}"`;
  process.env.FAKE_SUPABASE_LOG = logFile;
  // The preview project ref, so assertPreviewApplyTarget lets --apply through. Nothing ever
  // connects to it: PATH decides which (fake) executable is reached.
  process.env.DATABASE_URL = "postgresql://postgres.rjyboqwcdzcocqgmsyel@127.0.0.1:5432/postgres";
  delete process.env.SUPABASE_DB_URL;
});

after(() => {
  for (const [n, v] of Object.entries(SAVED)) {
    if (v === undefined) delete process.env[n];
    else process.env[n] = v;
  }
  if (stubDir) rmSync(stubDir, { recursive: true, force: true });
  if (emptyDir) rmSync(emptyDir, { recursive: true, force: true });
});

function usePath(dir) {
  process.env.PATH = dir;
  if (process.platform === "win32") process.env.Path = dir;
}

/** Run main() with stdout/stderr captured. */
function runMain(argv) {
  writeFileSync(logFile, "");
  const out = [];
  const err = [];
  const so = process.stdout.write.bind(process.stdout);
  const se = process.stderr.write.bind(process.stderr);
  process.stdout.write = (c) => (out.push(String(c)), true);
  process.stderr.write = (c) => (err.push(String(c)), true);
  try {
    return { code: main(argv, process.env), out: out.join(""), err: err.join("") };
  } finally {
    process.stdout.write = so;
    process.stderr.write = se;
  }
}

/** Every SQL statement the fake CLI was actually asked to run. */
function sqlSent() {
  const raw = readFileSync(logFile, "utf8").trim();
  return raw ? raw.split("\n").map((l) => JSON.parse(l).sql) : [];
}

test("runSql tags a real spawn-level fault CLIENT_SPAWN_FAULT, not a SQL error", () => {
  usePath(emptyDir); // neither psql nor supabase exists -> a genuine ENOENT from the OS
  let caught = null;
  try {
    readCycleState({ linked: true });
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, "an unreachable CLI must throw");
  assert.equal(caught.code, CLIENT_SPAWN_FAULT_CODE);
  assert.ok(isClientSpawnFault(caught));
  assert.equal(caught.spawnErrorCode, "ENOENT");
  assert.match(caught.message, /CLIENT-SIDE tooling fault, not a database failure/);
});

test("a client tooling fault exits 4 and records NOTHING — the breaker is untouched", () => {
  usePath(emptyDir);
  const { code, err } = runMain(["--apply"]);

  assert.equal(code, EXIT_CLIENT_TOOLING_FAULT, "must not take the failure path (1)");
  assert.notEqual(code, 0, "and must not be reported as success either");
  assert.match(err, /CLIENT TOOLING FAULT/);
  assert.match(err, /does NOT count toward the two-consecutive-failure circuit breaker/);

  // The proof: the durable-failure path was never even attempted. Had it been, its own runSql
  // calls would have failed too and printed these warnings.
  assert.doesNotMatch(err, /could not record the durable promotion alert/);
  assert.doesNotMatch(err, /could not record durable failure/);
  assert.deepEqual(sqlSent(), [], "no SQL of any kind may be sent after a spawn fault");
});

test("a REAL database failure still records both durable rows — the guard is not too wide", () => {
  usePath(stubDir); // the fake CLI runs and exits 1 with a SQL error on stderr
  const { code, err } = runMain(["--apply"]);

  assert.equal(code, 1, "a genuine SQL failure must still take the failure path");
  const sent = sqlSent();
  assert.ok(
    sent.some((s) => s.includes("record_taxonomy_sync_alert")),
    "the critical alert that trips the breaker autotrip must still be attempted",
  );
  assert.ok(
    sent.some((s) => s.includes("insert into ingest.sync_run")),
    "the durable failed sync_run row must still be attempted",
  );
  assert.match(err, /ColdLion recurring promotion FAILED at stage read-cycle-state/);
});

test("the tooling-fault exit code is distinct from every other outcome", () => {
  assert.equal(EXIT_CLIENT_TOOLING_FAULT, 4);
  for (const other of [0, 1, 2, EXIT_SKIPPED_ALREADY_RUNNING]) {
    assert.notEqual(EXIT_CLIENT_TOOLING_FAULT, other);
  }
});
