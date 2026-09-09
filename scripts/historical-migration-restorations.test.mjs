import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { HISTORICAL_RESTORATIONS, validateHistoricalProductionProvenance, validateHistoricalRestorationFile } from './historical-migration-restorations.mjs'

test('pins the issue 2501 restoration without changing production eligibility',()=>{
  const row=HISTORICAL_RESTORATIONS['20260907154630']
  assert.equal(row.filename,'supabase/migrations/20260907154630_popdam_tag_totals_cold_plan.sql')
  assert.equal(row.fileSha256,'90f49bc0d9cb34e44f3a795f1b15c05add6edcb0a24c261852fa9a106f615ead')
  assert.equal(row.statementBytes,10781)
  assert.equal(row.statementSha256,'08d1e2f6a71c44c7231dcef4cacb60326dbd128491cefc6e753d59eea609c099')
  assert.equal(Object.isFrozen(row),true)
  assert.deepEqual(row.objects,[
    'function public.filter_effective_assets',
    'function public.get_effective_filter_counts',
    'function public.get_filter_counts',
  ])
  assert.throws(
    ()=>validateHistoricalRestorationFile('supabase/migrations/20260907154630_wrong.sql','select 1;'),
    /not an approved exact historical restoration/,
  )
  assert.throws(
    ()=>validateHistoricalRestorationFile(row.filename,'select 1;'),
    /historical restoration file hash mismatch for 20260907154630/,
  )
})

test('pins the issue 2506 preview restoration without granting production eligibility',()=>{
  const row=HISTORICAL_RESTORATIONS['20260908214749']
  assert.equal(row.filename,'supabase/migrations/20260908214749_popsg_search_v2_bounded_paging.sql')
  assert.equal(row.name,'popsg_search_v2_bounded_paging')
  assert.equal(row.previewProject,'mvpkijzfmfcxhnzqogzs')
  assert.equal(row.previewApplyRun,'34290415305')
  assert.equal(row.previewDispatchCommit,'281b967986b7cca99b13722f4d9ed3c988902c9d')
  assert.equal(row.previewAppliedCommit,'281b967986b7cca99b13722f4d9ed3c988902c9d')
  assert.equal(row.fileSha256,'e79a608eedbfc31dab4c70acb2ad2709f3f4d56ee8d2bb7c3e6d43a96632968f')
  assert.equal(row.statementBytes,25052)
  assert.equal(row.statementSha256,'fe5982e1dd711ef7e136727323cb125d6b095ab83de9edd5eaa3ad28258fb780')
  assert.equal(Object.isFrozen(row),true)
  assert.deepEqual(row.objects,['function public.search_style_guide_library_v2'])
  // The on-disk file must BE the pinned bytes, so the pin cannot drift from the tree.
  assert.equal(validateHistoricalRestorationFile(row.filename,readFileSync(row.filename,'utf8')),row)
  // One byte more and the pin refuses: the entry authorizes content, never a version.
  assert.throws(
    ()=>validateHistoricalRestorationFile(row.filename,readFileSync(row.filename,'utf8')+'-- changed'+String.fromCharCode(10)),
    /historical restoration file hash mismatch for 20260908214749/,
  )
  // Production producer provenance is deliberately unregistered for this version.
  assert.throws(
    ()=>validateHistoricalProductionProvenance(row.filename,readFileSync(row.filename,'utf8'),{
      version:'20260908214749',
      previewApplyRun:'34290415305',
      previewDispatchCommit:'281b967986b7cca99b13722f4d9ed3c988902c9d',
      previewAppliedCommit:'281b967986b7cca99b13722f4d9ed3c988902c9d',
      sourcePr:2542,
      sourceMergeCommit:'0'.repeat(40),
      artifactFileSha256:row.fileSha256,
    }),
    /not registered for production producer provenance/,
  )
})

test('pins the issue 2356 restoration without changing production eligibility',()=>{
  const row=HISTORICAL_RESTORATIONS['20260907152838']
  assert.equal(row.filename,'supabase/migrations/20260907152838_dam_asset_freshness_current_state.sql')
  assert.equal(row.fileSha256,'6c04610f8e63d7d67b5c74610a69e219f912fa1b7fb520d7839ab8a81d77e022')
  assert.equal(row.statementBytes,3747)
  assert.equal(row.statementSha256,'8f9179afb6f2e01cd6684b591dae5e996381036b733a964450aa464128edab05')
  assert.equal(Object.isFrozen(row),true)
  assert.deepEqual(row.objects,[
    'column dam.asset.first_seen_at',
    'column dam.asset.last_seen_at',
    'column dam.asset.missing_since',
    'constraint dam_asset_seen_order on dam.asset',
    'constraint dam_asset_missing_after_first_seen on dam.asset',
    'function dam.enforce_asset_freshness',
    'table dam.asset',
    'trigger dam_asset_freshness_guard on dam.asset',
  ])
  assert.throws(
    ()=>validateHistoricalRestorationFile('supabase/migrations/20260907152838_wrong.sql','select 1;\n'),
    /not an approved exact historical restoration/,
  )
  assert.throws(
    ()=>validateHistoricalRestorationFile(row.filename,'select 1;\n'),
    /historical restoration file hash mismatch for 20260907152838/,
  )
})

test('pins the issue 2509 preview restoration without changing production eligibility',()=>{
  const row=HISTORICAL_RESTORATIONS['20260907131728']
  assert.equal(row.filename,'supabase/migrations/20260907131728_popsg_preview_stats_indexed_categories.sql')
  assert.equal(row.previewProject,'mvpkijzfmfcxhnzqogzs')
  assert.equal(row.previewApplyRun,'34157812748')
  assert.equal(row.previewDispatchCommit,'4f093e3d4c97e4272d147d38e7243ec57d3c08f1')
  assert.equal(row.previewAppliedCommit,'bcc2603977678db73b4ca12d3ed1312a1bff64e2')
  assert.equal(row.sourcePr,2513)
  assert.equal(row.sourceMergeCommit,'c5f85ad3a98b7a5598e8c81a56735473d5bb5487')
  assert.equal(row.fileSha256,'03648ecbbee473f539c27f929a248c503c18d5fb906efe1409d11593cfdb5d7e')
  assert.equal(row.statementBytes,9125)
  assert.equal(row.statementSha256,'d273d46aa662d3ae24502da44e3226e9c5932c7646b8d5d430b76563fa9d2191')
  assert.equal(Object.isFrozen(row),true)
  assert.deepEqual(row.objects,[
    'function public.get_sg_preview_stats',
    'index public.idx_sgf_active_preview_category',
    'table public.style_guide_files',
  ])
  assert.throws(
    ()=>validateHistoricalRestorationFile('supabase/migrations/20260907131728_wrong.sql','select 1;\n'),
    /not an approved exact historical restoration/,
  )
  assert.throws(
    ()=>validateHistoricalRestorationFile(row.filename,'select 1;\n'),
    /historical restoration file hash mismatch for 20260907131728/,
  )
})

test('production provenance accepts only the exact issue 2509 restoration evidence',()=>{
  const row=HISTORICAL_RESTORATIONS['20260907131728']
  const raw=readFileSync(row.filename,'utf8')
  const evidence={
    version:'20260907131728',
    previewApplyRun:'34157812748',
    previewDispatchCommit:'4f093e3d4c97e4272d147d38e7243ec57d3c08f1',
    previewAppliedCommit:'bcc2603977678db73b4ca12d3ed1312a1bff64e2',
    sourcePr:2513,
    sourceMergeCommit:'c5f85ad3a98b7a5598e8c81a56735473d5bb5487',
    artifactFileSha256:'03648ecbbee473f539c27f929a248c503c18d5fb906efe1409d11593cfdb5d7e',
  }
  assert.equal(validateHistoricalProductionProvenance(row.filename,raw,evidence),row)
  for(const [key,value] of [
    ['version','20260907131729'],
    ['previewApplyRun','34157812749'],
    ['previewDispatchCommit','d'.repeat(40)],
    ['previewAppliedCommit','a'.repeat(40)],
    ['sourcePr',2512],
    ['sourceMergeCommit','b'.repeat(40)],
    ['artifactFileSha256','c'.repeat(64)],
  ])assert.throws(
    ()=>validateHistoricalProductionProvenance(row.filename,raw,{...evidence,[key]:value}),
    new RegExp(`mismatch for ${key}`),
  )
  assert.throws(
    ()=>validateHistoricalProductionProvenance(row.filename,raw+'-- changed bytes\n',evidence),
    /file hash mismatch/,
  )
  assert.throws(
    ()=>validateHistoricalProductionProvenance(
      HISTORICAL_RESTORATIONS['20260817150944'].filename,
      readFileSync(HISTORICAL_RESTORATIONS['20260817150944'].filename,'utf8'),
      evidence,
    ),
    /not registered for production producer provenance/,
  )
})

test('pins the one authenticated preview historical restoration',()=>{
  const row=HISTORICAL_RESTORATIONS['20260817150944']
  assert.equal(row.name,'sync_dflow_columns_onto_plm_designflow_copies')
  assert.equal(row.creatorSha256,'ede9ab5ebdcbbb7af5760ff9ce653aa402b0c53a41e2ee9bdf18121204e58b9a')
  assert.equal(row.previewProject,'mvpkijzfmfcxhnzqogzs')
  assert.deepEqual(row.objects,['table plm.rfqitem','table plm.gridviewstate','table plm.itemdetail'])
})

test('pins the production code-truth restoration without authorizing replay',()=>{
  const row=HISTORICAL_RESTORATIONS['20260828052706']
  assert.equal(row.sourceVersion,'20260817150944')
  assert.equal(row.verificationRun,'33169143850')
  assert.equal(row.productionProject,'qsllyeztdwjgirsysgai')
  assert.equal(validateHistoricalRestorationFile(row.filename,readFileSync(row.filename,'utf8')),row)
})

test('pins the Sample Tracking preview ledger restoration byte for byte',()=>{
  const row=HISTORICAL_RESTORATIONS['20260824150630']
  assert.equal(row.name,'sample_tracking_piece_split_and_transit_return')
  assert.equal(row.previewProject,'mvpkijzfmfcxhnzqogzs')
  assert.equal(row.fileSha256,'5e9829b2cab7f0462804acce18bccf0d65b9c88363e9e54290581513047f4a52')
  assert.equal(row.statementBytes,15811)
  assert.equal(validateHistoricalRestorationFile(row.filename,readFileSync(row.filename,'utf8')),row)
})

test('refuses wrong paths and bytes',()=>{
  assert.throws(()=>validateHistoricalRestorationFile('supabase/migrations/20260817150944_wrong.sql','select 1;\n'),/not an approved/)
  assert.throws(()=>validateHistoricalRestorationFile(HISTORICAL_RESTORATIONS['20260817150944'].filename,'select 1;\n'),/hash mismatch/)
})
