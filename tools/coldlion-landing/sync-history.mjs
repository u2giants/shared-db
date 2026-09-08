#!/usr/bin/env node
// The scheduled ongoing history sync.
//
//   node tools/coldlion-landing/sync-history.mjs [--windows 3] [--to 2026-09-07]
//
// It re-fetches the most recent N grid windows every run, because a window that is
// already loaded is skipped and a window that is not is completed. Trailing more than
// one window is deliberate: an order edited days after it was written falls in an older
// window, and a sync that only ever looked at the current week would never see it.
//
// It never marks a loaded window dirty and it never rewrites page evidence. Picking up a
// changed row is the change-log unit's job, not this one's.

import { readColdlionApiKey } from "../coldlion-sync-common.mjs";
import { isoDate, recentWindows } from "./lib/grid.mjs";
import { proveTarget } from "./lib/db.mjs";
import { COMPANY_CODE, PAGE_SIZE } from "./lib/scopes.mjs";
import { allScopes, ledgerKey, loadWindowScope, loadedWindows, scopeLabel } from "./lib/run-history.mjs";

export const DEFAULT_WINDOWS = 3;

export function parseArgs(argv) {
  const args = { windows: DEFAULT_WINDOWS, company: COMPANY_CODE, pageSize: PAGE_SIZE, dryRun: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    switch (flag) {
      case "--windows": args.windows = Number(value); index += 1; break;
      case "--to": args.to = value; index += 1; break;
      case "--company": args.company = value; index += 1; break;
      case "--page-size": args.pageSize = Number(value); index += 1; break;
      case "--dry-run": args.dryRun = true; break;
      default:
        throw new Error(`unknown argument ${flag}`);
    }
  }
  if (!args.to) args.to = isoDate(new Date());
  if (!Number.isInteger(args.windows) || args.windows < 1) {
    throw new Error("--windows must be a positive integer");
  }
  return args;
}

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const target = proveTarget();
  console.log(`target ${target.database} at ${target.host}`);

  const windows = recentWindows(args.to, args.windows);
  const done = loadedWindows({ companyCode: args.company });
  const work = [];
  for (const window of windows) {
    for (const scope of allScopes()) {
      if (!done.has(ledgerKey(scope, window))) work.push({ window, scope });
    }
  }
  console.log(
    `${windows.length} recent window(s) to ${args.to}; ${work.length} window/scope pair(s) outstanding`,
  );
  if (args.dryRun) return { outstanding: work.length, loaded: 0, failures: 0 };

  const apiKey = readColdlionApiKey();
  let loaded = 0;
  const failures = [];
  for (const { window, scope } of work) {
    try {
      const result = await loadWindowScope({
        scope,
        window,
        apiKey,
        companyCode: args.company,
        pageSize: args.pageSize,
        requestedBy: "coldlion-landing sync-history",
      });
      loaded += 1;
      console.log(
        `${window.from}..${window.to} ${scopeLabel(scope)} ${result.fetched.rows} row(s) loaded`,
      );
    } catch (error) {
      // One window's terminal failure is already recorded and alerted. The rest of the
      // schedule still runs, and the process exits non-zero so the run is not green.
      failures.push(`${window.from} ${scopeLabel(scope)}: ${error.message}`);
      console.error(`${window.from} ${scopeLabel(scope)} FAILED: ${error.message}`);
    }
  }
  if (failures.length > 0) {
    const error = new Error(`${failures.length} window/scope pair(s) failed`);
    error.failures = failures;
    throw error;
  }
  return { outstanding: work.length, loaded, failures: 0 };
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("sync-history.mjs")) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
