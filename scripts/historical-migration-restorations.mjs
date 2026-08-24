#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

export const HISTORICAL_RESTORATIONS = Object.freeze({
  '20260824150630': Object.freeze({
    filename: 'supabase/migrations/20260824150630_sample_tracking_piece_split_and_transit_return.sql',
    name: 'sample_tracking_piece_split_and_transit_return',
    previewProject: 'mvpkijzfmfcxhnzqogzs',
    creatorSha256: '7f4d74d1ffa4d74b239be01bcfa4261610d2107a08f2e3d967feede858b5a96c',
    statementCount: 1,
    statementBytes: 16170,
    statementSha256: '9f9ab6f638caed2ae1fe430253a3120c31f3f63fdbe32b54a6a4a96d5520bf3c',
    fileSha256: '106a23da6a15590c0e38309d2b1b213cf49900e3eeb3e5021afd0e1c5ceff6f9',
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
  const digest=createHash('sha256').update(raw,'utf8').digest('hex')
  if(digest!==record.fileSha256)throw new Error(`historical restoration file hash mismatch for ${version}`)
  const statement=raw.endsWith('\n')?raw.slice(0,-1):raw
  if(raw!==`${statement}\n`||Buffer.byteLength(statement)!==record.statementBytes||createHash('sha256').update(statement,'utf8').digest('hex')!==record.statementSha256)throw new Error(`historical restoration statement bytes mismatch for ${version}`)
  return record
}

if(import.meta.url===pathToFileURL(process.argv[1]??'').href){
  try {
    const filename=String(process.argv[3]??'')
    if(process.argv[2]!=='--allows-backdated')throw new Error('unsupported command')
    validateHistoricalRestorationFile(filename,readFileSync(filename,'utf8'))
    process.exitCode=0
  } catch (error) {
    console.error(error.message)
    process.exitCode=2
  }
}
