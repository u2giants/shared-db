#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildPreviewGraph, assertAcyclic } from './preview-graph.mjs'
import { canonicalJson, sha256 } from './evidence-bundle.mjs'

export const PREVIEW_CLASSIFIER_VERSION = 1
export const NO_DATABASE_PREVIEW = 'NO_DATABASE_PREVIEW'
export const DATABASE_PREVIEW_REQUIRED = 'DATABASE_PREVIEW_REQUIRED'
const NO_PREVIEW_IMPACTS = new Set(['documentation','reviewer-tooling','ci-workflow','read-only-test','application-only'])
const PREVIEW_REQUIRED_IMPACTS = new Set(['database-structure','database-behavior','database-permission','database-data','generated','ambiguous'])
const INVALIDATION_CONDITIONS = Object.freeze(['file-content-change','file-set-change','impact-evidence-change','applicable-check-change','classifier-version-change'])

export function databasePreviewRequiredFromEvidenceBundle(bundle){
  const identity=bundle?.identity
  if(!identity||bundle.bundle_id!==sha256(canonicalJson(identity)))throw new Error('database evidence bundle identity is unavailable or changed')
  const byPath=new Map()
  const add=(rows,impact,reason)=>{for(const row of rows??[]){const existing=byPath.get(row.path);if(existing&&existing.sha256!==row.sha256)throw new Error(`database evidence bundle disagrees on ${row.path}`);byPath.set(row.path,{path:row.path,sha256:row.sha256,impact,reason})}}
  add(identity.migrations,'database-structure','versioned migration executes against the database')
  add(identity.focused_files,'read-only-test','database contract evidence remains applicable')
  add(identity.verification_files,'database-behavior','production verification contract observes database behavior')
  add(identity.global_invalidators,'generated','global database guard input invalidates prior qualification')
  const files=[...byPath.values()].sort((a,b)=>a.path.localeCompare(b.path)),applicable_checks=['database-preview','exact-head-review','full-ci']
  const firstRequired=files.find((file)=>PREVIEW_REQUIRED_IMPACTS.has(file.impact))
  if(!firstRequired)throw new Error('database evidence bundle names no preview-requiring input')
  return {schema_version:1,decision:DATABASE_PREVIEW_REQUIRED,reason_code:`impact_${firstRequired.impact.replaceAll('-','_')}`,inspected_digest:sha256(canonicalJson({classifier_version:PREVIEW_CLASSIFIER_VERSION,files,applicable_checks})),files,applicable_checks,invalidated_by:[...INVALIDATION_CONDITIONS]}
}

export function validatePreviewClassification(value,inspectedFiles){
  if(!value||value.schema_version!==1||!Array.isArray(value.files)||!value.files.length)throw new Error('explicit schema-version-1 database preview classification is required')
  const known=new Set(['schema_version','decision','reason_code','inspected_digest','files','applicable_checks','invalidated_by'])
  if(Object.keys(value).some((key)=>!known.has(key)))throw new Error('database preview classification contains an unknown input')
  if(![NO_DATABASE_PREVIEW,DATABASE_PREVIEW_REQUIRED].includes(value.decision))throw new Error('database preview decision is unknown')
  if(!Array.isArray(value.applicable_checks)||!value.applicable_checks.length||value.applicable_checks.some((check)=>typeof check!=='string'||!check.trim()))throw new Error('database preview classification requires applicable checks')
  if(new Set(value.applicable_checks).size!==value.applicable_checks.length)throw new Error('database preview classification has duplicate applicable checks')
  if(canonicalJson(value.invalidated_by)!==canonicalJson(INVALIDATION_CONDITIONS))throw new Error('database preview invalidation conditions are incomplete or changed')
  const seen=new Set(),files=value.files.map((entry)=>{
    if(!entry||Object.keys(entry).some((key)=>!['path','sha256','impact','reason'].includes(key)))throw new Error('database preview classification file contains an unknown input')
    const normalized=String(entry?.path??'').replaceAll('\\','/')
    if(!normalized||normalized.startsWith('/')||normalized.split('/').includes('..')||seen.has(normalized))throw new Error('database preview classification has an unsafe or duplicate inspected path')
    seen.add(normalized)
    if(!/^[0-9a-f]{64}$/.test(String(entry?.sha256??'')))throw new Error(`database preview classification has an invalid file digest for ${normalized}`)
    if(!NO_PREVIEW_IMPACTS.has(entry?.impact)&&!PREVIEW_REQUIRED_IMPACTS.has(entry?.impact))throw new Error(`database preview classification has unknown impact for ${normalized}`)
    if(typeof entry?.reason!=='string'||!entry.reason.trim())throw new Error(`database preview classification has no impact reason for ${normalized}`)
    return {path:normalized,sha256:entry.sha256,impact:entry.impact,reason:entry.reason.trim()}
  }).sort((a,b)=>a.path.localeCompare(b.path))
  const checks=[...new Set(value.applicable_checks.map((check)=>check.trim()))].sort()
  if(!Array.isArray(inspectedFiles)||!inspectedFiles.length)throw new Error('exact inspected file set is required independently of the preview decision')
  const authoritative=inspectedFiles.map((entry)=>({path:String(entry?.path??'').replaceAll('\\','/'),sha256:String(entry?.sha256??'')})).sort((a,b)=>a.path.localeCompare(b.path))
  if(authoritative.some((entry)=>!entry.path||!/^[0-9a-f]{64}$/.test(entry.sha256))||new Set(authoritative.map((entry)=>entry.path)).size!==authoritative.length)throw new Error('exact inspected file set is malformed')
  if(canonicalJson(authoritative)!==canonicalJson(files.map(({path,sha256})=>({path,sha256}))))throw new Error('database preview classification does not cover the exact inspected file set and bytes')
  const inspectedDigest=sha256(canonicalJson({classifier_version:PREVIEW_CLASSIFIER_VERSION,files,applicable_checks:checks}))
  if(value.inspected_digest!==inspectedDigest)throw new Error('database preview classification digest does not match its exact inspected inputs')
  const required=files.filter((file)=>PREVIEW_REQUIRED_IMPACTS.has(file.impact))
  const expectedDecision=required.length?DATABASE_PREVIEW_REQUIRED:NO_DATABASE_PREVIEW
  const expectedReason=required.length?`impact_${required[0].impact.replaceAll('-','_')}`:'proven_non_database_change'
  if(value.decision!==expectedDecision||value.reason_code!==expectedReason)throw new Error('database preview decision or reason does not match inspected impacts')
  return {schema_version:1,decision:expectedDecision,reason_code:expectedReason,inspected_digest:inspectedDigest,files,applicable_checks:checks,invalidated_by:[...INVALIDATION_CONDITIONS]}
}

export function selectPreviewRoute(input){
  try{
    if(!/^[0-9a-f]{40}$/i.test(String(input.head_sha??''))||!Number.isInteger(input.pr)||!Number.isInteger(input.issue))throw new Error('exact issue, PR and head are required')
    if(!/^[0-9a-f]{64}$/.test(String(input.bundle_id??'')))throw new Error('bundle identity is unavailable')
    const classification=validatePreviewClassification(input.database_preview,input.inspected_files)
    if(classification.decision===NO_DATABASE_PREVIEW){
      const context={issue:input.issue,pr:input.pr,head_sha:input.head_sha,bundle_id:input.bundle_id,route:NO_DATABASE_PREVIEW,classification_digest:classification.inspected_digest,reason_code:classification.reason_code,applicable_checks:classification.applicable_checks}
      return {status:'READY',route:NO_DATABASE_PREVIEW,reason:'exact inspected inputs prove no database preview is applicable',context,decision_id:sha256(canonicalJson(context)),classification}
    }
    if(!Array.isArray(input.versions)||!input.versions.length||input.versions.some((version)=>!/^\d{14}$/.test(String(version))))throw new Error('versions must be a non-empty 14-digit array')
    if(input.dependency_closure_complete!==true)throw new Error('migration dependency closure is not proven')
    const claims=[...(input.claims??[])]
    if(!claims.some((claim)=>claim.pr===input.pr))claims.push({issue:input.issue,pr:input.pr,versions:input.versions,merged:Boolean(input.merged)})
    const graph=assertAcyclic(buildPreviewGraph({mainVersions:input.main_versions,previewVersions:input.preview_versions,claims}))
    const requested=new Set(input.versions.map(String)),main=new Set(input.main_versions.map(String)),preview=new Set(input.preview_versions.map(String))
    const blockers=graph.edges.filter((edge)=>requested.has(edge.to)&&!requested.has(edge.from)).map((edge)=>edge.from)
    let route,reason
    if(blockers.length){route='WAITING';reason=`preview contains unmerged predecessor(s): ${[...new Set(blockers)].join(', ')}`}
    else if([...requested].every((version)=>preview.has(version))){
      if(!['preview-apply','preview-ledger-reconciliation'].includes(input.original_apply_evidence?.type)||!/^[0-9]+$/.test(String(input.original_apply_evidence.run_id??'')))throw new Error('already-applied versions require typed immutable preview evidence')
      route=input.merged?'PREVIEW_REBIND':'HISTORICAL_RECOVERY';reason='requested bytes already exist on preview; never reapply'
    }else if(input.merged){
      if(![...requested].every((version)=>main.has(version)))throw new Error('merged route versions are not all on current main')
      route='POST_MERGE_REHEARSAL';reason='merged versions are absent from preview'
    }else{route='NORMAL_PREVIEW';reason='open exact-head versions are absent from preview'}
    const context={issue:input.issue,pr:input.pr,head_sha:input.head_sha,bundle_id:input.bundle_id,versions:[...requested].sort(),graph_digest:graph.digest,route,blockers:[...new Set(blockers)].sort(),classification_digest:classification.inspected_digest,reason_code:classification.reason_code}
    return {status:route==='WAITING'?'WAITING':'READY',route,reason,context,decision_id:sha256(canonicalJson(context)),graph}
  }catch(error){return {status:'UNVERIFIABLE',route:'UNVERIFIABLE',reason:error.message}}
}

export function main(argv){const index=argv.indexOf('--input');if(index<0||!argv[index+1]){console.error('REFUSED: --input <json> is required');return 2}try{const result=selectPreviewRoute(JSON.parse(readFileSync(argv[index+1],'utf8')));console.log(JSON.stringify(result,null,2));return result.status==='UNVERIFIABLE'?2:0}catch(error){console.error(`REFUSED: ${error.message}`);return 2}}
if(process.argv[1]&&path.resolve(fileURLToPath(import.meta.url))===path.resolve(process.argv[1]))process.exitCode=main(process.argv.slice(2))
