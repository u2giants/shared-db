import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { HISTORICAL_RESTORATIONS, validateHistoricalRestorationFile } from './historical-migration-restorations.mjs'

test('pins the issue 2509 preview restoration without changing production eligibility',()=>{
  const row=HISTORICAL_RESTORATIONS['20260907131728']
  assert.equal(row.filename,'supabase/migrations/20260907131728_popsg_preview_stats_indexed_categories.sql')
  assert.equal(row.previewProject,'mvpkijzfmfcxhnzqogzs')
  assert.equal(row.previewApplyRun,'34157812748')
  assert.equal(row.previewAppliedCommit,'bcc2603977678db73b4ca12d3ed1312a1bff64e2')
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
