import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fetchArrayMaster, fetchPagedMaster, masterUrl } from "./coldlion-landing/lib/master-http.mjs";
import { ITEM_SPECS, MASTER_SPECS, knownApiFields } from "./coldlion-landing/lib/master-specs.mjs";
import { assertKnownShape, projectCurrentRows, projectItemSlots } from "./coldlion-landing/lib/project-masters.mjs";
import { buildMasterLoadSql } from "./coldlion-landing/lib/load-masters.mjs";
import { main, parseArgs } from "./coldlion-landing/sync-masters.mjs";

const RUN="11111111-1111-4111-8111-111111111111";
const NOW="2026-09-09T00:00:00.000Z";

function sourceFor(spec, overrides={}) {
  const row={};
  for (const field of spec.fields) {
    row[field.api]=field.type === "num" ? "1.25" : field.type === "date" ? "2026-01-02" : field.type === "ts" ? "2026-01-02T03:04:05Z" : `SYN-${field.api}`;
  }
  for (const ignored of spec.ignored ?? []) row[ignored]=null;
  if (spec.slots) for (let n=1;n<=14;n+=1) { const nn=String(n).padStart(2,"0"); row[`merchGroup${nn}`]=n===1?"SYN-MG":null; row[`merchGroup${nn}Desc`]=n===1?"Synthetic group":null; }
  return {...row,...overrides};
}

test("parameter snapshot predates loader implementation and covers every requested endpoint",()=>{
  const doc=JSON.parse(readFileSync("docs/verification/coldlion-api-parameters-20260909T022136Z.json","utf8"));
  for (const path of ["/customers","/vendors","/divisions","/salespersons","/seasons","/merchGroupHeaders","/merchGroupDetails","/items","/itemDetails"]) assert.ok(doc.endpoints[path]);
  assert.deepEqual(doc.endpoints["/merchGroupDetails"].filter((x)=>x.startsWith("query:")),["query:active(default=Y)","query:companyCode","query:divisionCode","query:mgCode","query:mgTypeCode"]);
});

test("operational probe proves merchGroupDetails works without retaining values",()=>{
  const proof=JSON.parse(readFileSync("docs/verification/coldlion-merch-group-details-probe-20260909T0224Z.json","utf8"));
  assert.equal(proof.response_shape,"plain array"); assert.ok(proof.nonempty_queries>0); assert.match(proof.privacy,/no ColdLion payload values/i);
});

test("merchandise detail identity includes category so live categories cannot collapse",()=>{
  assert.deepEqual(MASTER_SPECS.merch_group_detail.key,["company_code","division_code","mg_type_code","mg_category","mg_code"]);
  const source=sourceFor(MASTER_SPECS.merch_group_detail,{companyCode:"SYNCO",divisionCode:"SD001",mgTypeCode:"01",mgCategory:"",mgCode:"M1"});
  const projected=projectCurrentRows(MASTER_SPECS.merch_group_detail,[source],{runId:RUN,fetchedAt:NOW});
  assert.equal(projected.rows[0].mg_category,"");
});

test("master URL emits only declared parameters supplied by its caller",()=>{
  assert.equal(masterUrl("/seasons",{companyCode:"SYNCO",divisionCode:"SD001",active:"N"}).search,"?companyCode=SYNCO&divisionCode=SD001&active=N");
});

test("paged masters walk to last and prove the vendor total",async()=>{
  let calls=0;
  const fetchImpl=async(url)=>{ const page=Number(new URL(url).searchParams.get("page")); calls+=1; const content=page===0?[{id:1},{id:2}]:[{id:3}]; return {ok:true,status:200,text:async()=>JSON.stringify({content,number:page,size:2,numberOfElements:content.length,totalElements:3,totalPages:2,last:page===1})}; };
  const rows=await fetchPagedMaster("/customers",{companyCode:"SYNCO"},"hidden",{fetchImpl,pauseMs:0});
  assert.equal(rows.length,3); assert.equal(calls,2);
});

test("paged masters refuse an incomplete total",async()=>{
  const fetchImpl=async()=>({ok:true,status:200,text:async()=>JSON.stringify({content:[{}],number:0,size:2,numberOfElements:1,totalElements:2,totalPages:1,last:true})});
  await assert.rejects(fetchPagedMaster("/customers",{},"hidden",{fetchImpl,pauseMs:0}),/incomplete/);
});

test("plain-array endpoints refuse a paged envelope",async()=>{
  const fetchImpl=async()=>({ok:true,status:200,text:async()=>JSON.stringify({content:[]})});
  await assert.rejects(fetchArrayMaster("/itemDetails",{},"hidden",{fetchImpl,pauseMs:0}),/plain array/);
});

test("plain-array masters use the same serialized request gate",async()=>{
  let gates=0;
  const fetchImpl=async()=>({ok:true,status:200,text:async()=>"[]"});
  await fetchArrayMaster("/merchGroupDetails",{},"hidden",{fetchImpl,pauseMs:0,requestGate:async()=>{gates+=1;}});
  assert.equal(gates,1);
});

test("every live-shaped synthetic row maps or is deliberately ignored",()=>{
  for (const spec of [...Object.values(MASTER_SPECS),...Object.values(ITEM_SPECS)]) {
    const row=sourceFor(spec); assert.doesNotThrow(()=>assertKnownShape(spec,[row])); assert.ok(knownApiFields(spec).size>=spec.fields.length);
  }
});

test("unknown fields fail loudly before projection",()=>{
  assert.throws(()=>projectCurrentRows(MASTER_SPECS.vendor,[sourceFor(MASTER_SPECS.vendor,{newPrivateField:"x"})],{runId:RUN,fetchedAt:NOW}),/unreviewed field/);
});

test("current rows normalize sentinels, hash complete records, dedupe replay, and exclude EP001",()=>{
  const spec=MASTER_SPECS.season;
  const good=sourceFor(spec,{companyCode:"SYNCO",divisionCode:"SD001",seasonCode:"S1",createdTime:"1900-01-01"});
  const excluded=sourceFor(spec,{companyCode:"SYNCO",divisionCode:"EP001",seasonCode:"S2"});
  const result=projectCurrentRows(spec,[good,good,excluded],{runId:RUN,fetchedAt:NOW});
  assert.equal(result.rows.length,1); assert.equal(result.excluded,1); assert.equal(result.rows[0].created_time,null); assert.match(result.rows[0].source_hash,/^[0-9a-f]{64}$/);
});

test("conflicting duplicate natural keys abort",()=>{
  const spec=MASTER_SPECS.vendor;
  const a=sourceFor(spec,{companyCode:"SYNCO",vendorCode:"V1",vendorDesc:"A"});
  const b={...a,vendorDesc:"B"};
  assert.throws(()=>projectCurrentRows(spec,[a,b],{runId:RUN,fetchedAt:NOW}),/conflicting rows/);
});

test("item slots preserve header/detail grain and omit cleared slots",()=>{
  const header=sourceFor(ITEM_SPECS.item_header,{companyCode:"SYNCO",divisionCode:"SD001",itemNo:"ITEM-A"});
  const detail=sourceFor(ITEM_SPECS.item_detail,{companyCode:"SYNCO",divisionCode:"SD001",itemNo:"ITEM-A",itemPkey:"PK-1"});
  const h=projectItemSlots([header],{runId:RUN,fetchedAt:NOW}); const d=projectItemSlots([detail],{runId:RUN,fetchedAt:NOW,itemPkey:"source"});
  assert.equal(h.length,1); assert.equal(h[0].item_pkey,null); assert.equal(d[0].item_pkey,"PK-1");
});

test("generated SQL is a re-runnable upsert, reconciles cleared slots, and never uses history sealing",()=>{
  const order=["division","customer","vendor","salesperson","season","merch_group_header","merch_group_detail","item_header","item_detail"];
  const loads=order.map((table)=>{ const spec=MASTER_SPECS[table]??ITEM_SPECS[table]; const source=sourceFor(spec); const rows=projectCurrentRows(spec,[source],{runId:RUN,fetchedAt:NOW}).rows; return {table,spec,rows,run:{id:RUN,endpoint:spec.endpoint,companyCode:"SYNCO",requestParams:{fullSnapshot:true},requestedBy:"test",startedAt:NOW,finishedAt:NOW,durationMs:0,rowsFetched:1}}; });
  const source=sourceFor(ITEM_SPECS.item_header,{companyCode:"SYNCO",divisionCode:"SD001",itemNo:"ITEM-A"});
  const sql=buildMasterLoadSql({loads,itemSlots:projectItemSlots([source],{runId:RUN,fetchedAt:NOW}),affectedItemGrains:[{company_code:"SYNCO",division_code:"SD001",item_no:"ITEM-A",item_pkey:null}]});
  assert.match(sql,/on conflict \(company_code, customer_code\) do update/i); assert.match(sql,/delete from coldlion\.item_merch_group/i); assert.match(sql,/not exists \(select 1 from _stage_item_merch_group/i); assert.doesNotMatch(sql,/truncate|window_ledger|history_page_ledger/i); assert.equal((sql.match(/\bbegin;/gi)??[]).length,1); assert.equal((sql.match(/\bcommit;/gi)??[]).length,1);
});

test("CLI proves target before collection and write",async()=>{
  const calls=[];
  await main(["--dry-run"],{proveTarget:()=>{calls.push("prove");return{database:"synthetic",host:"local"}},readApiKey:()=>"hidden",collectMasters:async()=>{calls.push("collect");return{loads:[],itemSlots:[],affectedItemGrains:[]}},runSql:()=>calls.push("write")});
  assert.deepEqual(calls,["prove","collect"]);
});

test("CLI arguments do not expose history controls",()=>{
  assert.deepEqual(parseArgs([]),{company:"EDGEHOME",dryRun:false}); assert.throws(()=>parseArgs(["--windows","3"]),/unknown argument/);
});

test("workflow is the sole live path and runs masters before history",()=>{
  const yaml=readFileSync(".github/workflows/coldlion-landing-sync.yml","utf8");
  assert.match(yaml,/SUPABASE_DB_URL_PRODUCTION/); assert.match(yaml,/COLDLION_EXPECTED_PROJECT_REF: qsllyeztdwjgirsysgai/); assert.match(yaml,/COLDLION_API_KEY/); assert.doesNotMatch(yaml,/pull_request:|push:/);
  assert.ok(yaml.indexOf("sync-masters.mjs")<yaml.indexOf("sync-history.mjs")); assert.match(yaml,/coldlion-landing-masters\.test\.mjs/);
});
