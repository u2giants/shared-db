#!/usr/bin/env node
// Full current-state ColdLion master sync. No history window, window ledger, or sealing rule
// appears here: every run may re-fetch and upsert every master row.

import { randomUUID } from "node:crypto";
import { readColdlionApiKey } from "../coldlion-sync-common.mjs";
import { proveTarget, runSql } from "./lib/db.mjs";
import { fetchMasterSpec } from "./lib/master-http.mjs";
import { ITEM_SPECS, MASTER_SPECS } from "./lib/master-specs.mjs";
import { projectCurrentRows, projectItemSlots } from "./lib/project-masters.mjs";
import { buildMasterLoadSql } from "./lib/load-masters.mjs";

export const COMPANY_CODE = "EDGEHOME";

export function parseArgs(argv) {
  const args = { company: COMPANY_CODE, dryRun: false };
  for (let index=0; index<argv.length; index+=1) {
    if (argv[index] === "--company") { args.company=argv[++index]; continue; }
    if (argv[index] === "--dry-run") { args.dryRun=true; continue; }
    throw new Error(`unknown argument ${argv[index]}`);
  }
  if (!args.company?.trim()) throw new Error("--company must not be blank");
  return args;
}

function makeGate(pauseMs = 3000) {
  let next = Promise.resolve();
  return () => { next = next.then(() => new Promise((done) => setTimeout(done, pauseMs))); return next; };
}

async function fetchVariants(spec, baseParams, apiKey, options) {
  if (!spec.active) return fetchMasterSpec(spec, baseParams, apiKey, options);
  const rows = [];
  for (const active of ["Y","N"]) rows.push(...await fetchMasterSpec(spec, { ...baseParams, active }, apiKey, options));
  return rows;
}

function makeLoad(table, spec, sourceRows, requestedBy, startedAt, finishedAt, companyCode) {
  const id = randomUUID();
  const projected = projectCurrentRows(spec, sourceRows, { runId: id, fetchedAt: finishedAt });
  return {
    table, spec, rows: projected.rows, excluded: projected.excluded,
    run: { id, endpoint: spec.endpoint, companyCode, requestParams: { companyCode, fullSnapshot: true }, requestedBy, startedAt, finishedAt, durationMs: Math.max(0, new Date(finishedAt)-new Date(startedAt)), rowsFetched: sourceRows.length },
  };
}

export async function collectMasters({ companyCode=COMPANY_CODE, apiKey, fetchOptions={} } = {}) {
  const options = { requestGate: makeGate(fetchOptions.pauseMs ?? 3000), ...fetchOptions };
  const startedAt = new Date().toISOString();
  const source = {};
  for (const name of ["division","customer","vendor","salesperson"]) {
    source[name] = await fetchVariants(MASTER_SPECS[name], { companyCode }, apiKey, options);
  }
  const divisions = [...new Set(source.division.map((row)=>row.divisionCode).filter((code)=>code && code !== "EP001"))];
  source.season = [];
  for (const divisionCode of divisions) {
    source.season.push(...await fetchVariants(MASTER_SPECS.season, { companyCode, divisionCode }, apiKey, options));
  }
  source.merch_group_header = await fetchVariants(MASTER_SPECS.merch_group_header, { companyCode }, apiKey, options);
  source.merch_group_detail = await fetchVariants(MASTER_SPECS.merch_group_detail, { companyCode }, apiKey, options);
  source.item_header = await fetchMasterSpec(ITEM_SPECS.item_header, { companyCode }, apiKey, options);
  source.item_detail = await fetchMasterSpec(ITEM_SPECS.item_detail, { companyCode }, apiKey, options);

  const finishedAt = new Date().toISOString();
  const loads = [];
  for (const name of ["division","customer","vendor","salesperson","season","merch_group_header","merch_group_detail","item_header","item_detail"]) {
    const spec = MASTER_SPECS[name] ?? ITEM_SPECS[name];
    loads.push(makeLoad(name, spec, source[name], "coldlion-landing sync-masters", startedAt, finishedAt, companyCode));
  }
  const byTable = Object.fromEntries(loads.map((load)=>[load.table,load]));
  const itemSlots = [
    ...projectItemSlots(source.item_header, { runId: byTable.item_header.run.id, fetchedAt: finishedAt }),
    ...projectItemSlots(source.item_detail, { runId: byTable.item_detail.run.id, fetchedAt: finishedAt, itemPkey: "source" }),
  ];
  const affectedItemGrains = [
    ...byTable.item_header.rows.map((r)=>({company_code:r.company_code,division_code:r.division_code,item_no:r.item_no,item_pkey:null})),
    ...byTable.item_detail.rows.map((r)=>({company_code:r.company_code,division_code:r.division_code,item_no:r.item_no,item_pkey:r.item_pkey})),
  ];
  return { loads, itemSlots, affectedItemGrains };
}

export async function main(argv=process.argv.slice(2), dependencies={}) {
  const args=parseArgs(argv);
  const prove=dependencies.proveTarget ?? proveTarget;
  const execute=dependencies.runSql ?? runSql;
  const readKey=dependencies.readApiKey ?? readColdlionApiKey;
  const collect=dependencies.collectMasters ?? collectMasters;
  const target=prove();
  console.log(`target ${target.database} at ${target.host}`);
  const result=await collect({companyCode:args.company,apiKey:readKey()});
  for (const load of result.loads) console.log(`${load.run.endpoint}: fetched ${load.run.rowsFetched}, landing ${load.rows.length}, excluded ${load.excluded}`);
  console.log(`item merchandise-group slots: ${result.itemSlots.length}`);
  if (!args.dryRun) execute(buildMasterLoadSql(result));
  return result;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("sync-masters.mjs")) {
  main().catch((error)=>{ console.error(error.message); process.exitCode=1; });
}
