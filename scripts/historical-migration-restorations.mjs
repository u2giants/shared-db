#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

export const HISTORICAL_RESTORATIONS = Object.freeze({
  // #2356. The protected version and exact migration bytes were authored on
  // PR #2523 before 20260907200221 reached main. This entry permits only those
  // exact bytes to survive the backdated-version guard; it does not mark the
  // migration preview-only or otherwise change its production eligibility.
  '20260907152838': Object.freeze({
    filename: 'supabase/migrations/20260907152838_dam_asset_freshness_current_state.sql',
    name: 'dam_asset_freshness_current_state',
    statementBytes: 3747,
    statementSha256: '8f9179afb6f2e01cd6684b591dae5e996381036b733a964450aa464128edab05',
    fileSha256: '6c04610f8e63d7d67b5c74610a69e219f912fa1b7fb520d7839ab8a81d77e022',
    objects: Object.freeze([
      'column dam.asset.first_seen_at',
      'column dam.asset.last_seen_at',
      'column dam.asset.missing_since',
      'constraint dam_asset_seen_order on dam.asset',
      'constraint dam_asset_missing_after_first_seen on dam.asset',
      'function dam.enforce_asset_freshness',
      'table dam.asset',
      'trigger dam_asset_freshness_guard on dam.asset',
    ]),
  }),
  // #2509. Preview applied these exact bytes in run 34157812748 from PR #2513
  // commit bcc2603977678db73b4ca12d3ed1312a1bff64e2. Migration 20260907200221
  // then reached main first, so the unchanged source-restoration sorts behind
  // main. This pin authorizes only the exact applied file; it does not make the
  // version preview-only or otherwise change its production eligibility.
  '20260907131728': Object.freeze({
    filename: 'supabase/migrations/20260907131728_popsg_preview_stats_indexed_categories.sql',
    name: 'popsg_preview_stats_indexed_categories',
    previewProject: 'mvpkijzfmfcxhnzqogzs',
    previewApplyRun: '34157812748',
    previewDispatchCommit: '4f093e3d4c97e4272d147d38e7243ec57d3c08f1',
    previewAppliedCommit: 'bcc2603977678db73b4ca12d3ed1312a1bff64e2',
    sourcePr: 2513,
    sourceMergeCommit: 'c5f85ad3a98b7a5598e8c81a56735473d5bb5487',
    statementBytes: 9125,
    statementSha256: 'd273d46aa662d3ae24502da44e3226e9c5932c7646b8d5d430b76563fa9d2191',
    fileSha256: '03648ecbbee473f539c27f929a248c503c18d5fb906efe1409d11593cfdb5d7e',
    objects: Object.freeze([
      'function public.get_sg_preview_stats',
      'index public.idx_sgf_active_preview_category',
      'table public.style_guide_files',
    ]),
  }),
  // #2035. Preview applied this version in run 33454217961 from PR #2009 commit
  // bb77fdd49fe032c985dc93c907f5d4d93a2456a1, then the PR head moved twice to fix two
  // High review findings and the corrected body merged as 30221c0b. Preview therefore
  // holds the seven hts_rag_* tables from the SUPERSEDED body, and the production
  // business-risk gate refuses a promotion whose rehearsal digest is not the file on
  // exact main. Preview cannot re-run `create table`, so the file is restored to the
  // bytes preview actually ran and the corrections are fixed forward in 20260901011306.
  '20260831234750': Object.freeze({
    filename: 'supabase/migrations/20260831234750_hts_rag_durable_precedent_contract.sql',
    name: 'hts_rag_durable_precedent_contract',
    previewProject: 'mvpkijzfmfcxhnzqogzs',
    previewApplyRun: '33454217961',
    previewAppliedCommit: 'bb77fdd49fe032c985dc93c907f5d4d93a2456a1',
    forwardFixVersion: '20260901011306',
    statementBytes: 12578,
    statementSha256: '646bc6be0bef4e5bcc09cc944a46ff8910d9cab72a6b19ce66f3df60e2e15af4',
    fileSha256: '2931391a44f512ec80fe468b00c3b92c277397418e5fda25fa98907dad6559cb',
    objects: Object.freeze([
      'table public.hts_rag_precedents',
      'table public.hts_rag_precedent_rulings',
      'table public.hts_rag_product_examples',
      'table public.hts_rag_determinations',
      'table public.hts_rag_extraction_jobs',
      'table public.hts_rag_review_events',
      'table public.hts_rag_product_family_allowlist',
    ]),
  }),
  '20260828052706': Object.freeze({
    filename: 'supabase/migrations/20260828052706_sync_dflow_columns_onto_plm_designflow_copies.sql',
    name: 'sync_dflow_columns_onto_plm_designflow_copies',
    productionProject: 'qsllyeztdwjgirsysgai',
    sourceVersion: '20260817150944',
    verificationRun: '33169143850',
    codeTruthOnly: true,
    statementCount: 1,
    statementBytes: 3213,
    statementSha256: '03f40fec5d4d72443b31ac5c7bdb028d4972eedf057479c596214efb1b189779',
    fileSha256: 'c8ab692586a94fef5dfdf18b32105ccb9f9469bb8336c40fab793c1c4404dace',
    objects: Object.freeze(['table plm.rfqitem','table plm.gridviewstate','table plm.itemdetail']),
  }),
  '20260824150630': Object.freeze({
    filename: 'supabase/migrations/20260824150630_sample_tracking_piece_split_and_transit_return.sql',
    name: 'sample_tracking_piece_split_and_transit_return',
    previewProject: 'mvpkijzfmfcxhnzqogzs',
    creatorSha256: '7f4d74d1ffa4d74b239be01bcfa4261610d2107a08f2e3d967feede858b5a96c',
    statementCount: 1,
    statementBytes: 15811,
    statementSha256: 'fa01a4f5cf7a944bfbba2faa0176a696beca64bb69e838869a8e085019a1ab77',
    fileSha256: '5e9829b2cab7f0462804acce18bccf0d65b9c88363e9e54290581513047f4a52',
    objects: Object.freeze([
      'function dflow.post_sample_piece_split',
      'function dflow.validate_sample_movement_shipment_identity',
      'table dflow.sample_movement',
      'view dflow.sample_global_status',
      'function dflow.sample_movement_guard',
    ]),
  }),
  '20260817150944': Object.freeze({
    filename: 'supabase/migrations/20260817150944_sync_dflow_columns_onto_plm_designflow_copies.sql',
    name: 'sync_dflow_columns_onto_plm_designflow_copies',
    previewProject: 'mvpkijzfmfcxhnzqogzs',
    creatorSha256: 'ede9ab5ebdcbbb7af5760ff9ce653aa402b0c53a41e2ee9bdf18121204e58b9a',
    statementCount: 1,
    statementBytes: 3213,
    statementSha256: '03f40fec5d4d72443b31ac5c7bdb028d4972eedf057479c596214efb1b189779',
    fileSha256: 'c8ab692586a94fef5dfdf18b32105ccb9f9469bb8336c40fab793c1c4404dace',
    objects: Object.freeze(['table plm.rfqitem','table plm.gridviewstate','table plm.itemdetail']),
  }),
})

export function validateHistoricalRestorationFile(filename, raw) {
  const version=path.basename(filename).slice(0,14), record=HISTORICAL_RESTORATIONS[version]
  if(!record||filename.replaceAll('\\','/')!==record.filename)throw new Error('file is not an approved exact historical restoration')
  const governedRaw=raw.replaceAll('\r\n','\n')
  const digest=createHash('sha256').update(governedRaw,'utf8').digest('hex')
  if(digest!==record.fileSha256)throw new Error(`historical restoration file hash mismatch for ${version}`)
  const statement=governedRaw.endsWith('\n')?governedRaw.slice(0,-1):governedRaw
  if(governedRaw!==`${statement}\n`||Buffer.byteLength(statement)!==record.statementBytes||createHash('sha256').update(statement,'utf8').digest('hex')!==record.statementSha256)throw new Error(`historical restoration statement bytes mismatch for ${version}`)
  return record
}

export function validateHistoricalProductionProvenance(filename, raw, evidence) {
  const record=validateHistoricalRestorationFile(filename,raw)
  const expected={
    version:path.basename(filename).slice(0,14),
    previewApplyRun:record.previewApplyRun,
    previewDispatchCommit:record.previewDispatchCommit,
    previewAppliedCommit:record.previewAppliedCommit,
    sourcePr:record.sourcePr,
    sourceMergeCommit:record.sourceMergeCommit,
    artifactFileSha256:record.fileSha256,
  }
  if(!record.sourcePr||!record.sourceMergeCommit)throw new Error('historical restoration is not registered for production producer provenance')
  if(!evidence||typeof evidence!=='object'||Array.isArray(evidence)||Object.keys(evidence).sort().join(',')!==Object.keys(expected).sort().join(','))throw new Error('historical production provenance evidence has an incomplete schema')
  for(const [key,value] of Object.entries(expected))if(evidence[key]!==value)throw new Error(`historical production provenance mismatch for ${key}`)
  return record
}

if(import.meta.url===pathToFileURL(process.argv[1]??'').href){
  try {
    const filename=String(process.argv[3]??'')
    if(process.argv[2]==='--allows-backdated')validateHistoricalRestorationFile(filename,readFileSync(filename,'utf8'))
    else if(process.argv[2]==='--production-provenance'){
      const record=validateHistoricalProductionProvenance(filename,readFileSync(filename,'utf8'),JSON.parse(String(process.argv[4]??'')))
      process.stdout.write(JSON.stringify({version:path.basename(filename).slice(0,14),fileSha256:record.fileSha256})+'\n')
    } else throw new Error('unsupported command')
    process.exitCode=0
  } catch (error) {
    console.error(error.message)
    process.exitCode=2
  }
}
