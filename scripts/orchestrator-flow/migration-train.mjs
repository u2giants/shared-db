import { canonicalJson, sha256 } from './evidence-bundle.mjs'

export class MigrationTrainError extends Error {}
export const TRAIN_REF_PREFIX='refs/db-migration-trains'
export const TRAIN_STATES=Object.freeze(['proposed','authorized','dispatched','closed','failed'])
const VERSION=/^\d{14}$/, SHA=/^[0-9a-f]{40}$/i, DIGEST=/^[0-9a-f]{64}$/i

const trainRef=(record)=>`${TRAIN_REF_PREFIX}/${record.train_id}/${String(record.generation).padStart(6,'0')}-${record.state}`
const recordDigest=(record)=>sha256(canonicalJson(record))
const sameRecord=(left,right)=>canonicalJson(left)===canonicalJson(right)
const PREDECESSOR_STATES=Object.freeze({authorized:['proposed'],dispatched:['authorized','failed'],failed:['dispatched'],closed:['dispatched']})

function assertLifecycleChain(record,io,seen=new Set()){
  if(!Number.isSafeInteger(record?.generation)||record.generation<1||!TRAIN_STATES.includes(record?.state))throw new MigrationTrainError('train lifecycle state or generation is malformed')
  const ref=trainRef(record)
  if(seen.has(ref))throw new MigrationTrainError('train lifecycle contains a predecessor cycle')
  seen.add(ref)
  if(record.generation===1){
    if(record.state!=='proposed'||record.previous_ref!==undefined||record.previous_digest!==undefined)throw new MigrationTrainError('train generation 1 must be the canonical proposal with no predecessor')
    if(!sameRecord(record,proposeTrain(record)))throw new MigrationTrainError('train generation 1 does not match its canonical manifest digest')
    return true
  }
  if(record.state==='proposed'||typeof record.previous_ref!=='string'||!DIGEST.test(String(record.previous_digest??'')))throw new MigrationTrainError('later train generation requires an exact predecessor ref and digest')
  const match=new RegExp(`^${TRAIN_REF_PREFIX}/${record.train_id}/(\\d{6})-(${TRAIN_STATES.join('|')})$`).exec(record.previous_ref)
  if(!match||Number(match[1])!==record.generation-1||!PREDECESSOR_STATES[record.state]?.includes(match[2]))throw new MigrationTrainError('train predecessor state or generation is not an allowed exact prior generation')
  const prior=io.readImmutable(record.previous_ref)
  if(!prior||prior.digest!==record.previous_digest||recordDigest(prior.record)!==record.previous_digest||trainRef(prior.record)!==record.previous_ref)throw new MigrationTrainError('train predecessor durable readback does not match its ref and digest')
  return assertLifecycleChain(prior.record,io,seen)
}

function requireExactEntries(entries){
  if(!Array.isArray(entries)||!entries.length)throw new MigrationTrainError('train requires a nonempty exact migration list')
  const seen=new Set()
  const normalized=entries.map((raw,index)=>{
    const entry={version:String(raw.version??''),file_sha256:String(raw.file_sha256??''),source_pr:Number(raw.source_pr),merge_sha:String(raw.merge_sha??''),dependencies:[...(raw.dependencies??[])].map(String).sort(),risk_class:String(raw.risk_class??''),role:String(raw.role??''),preview_assertion:String(raw.preview_assertion??''),production_assertion:String(raw.production_assertion??'')}
    if(!VERSION.test(entry.version)||!DIGEST.test(entry.file_sha256)||!Number.isInteger(entry.source_pr)||entry.source_pr<1||!SHA.test(entry.merge_sha)||!entry.risk_class||!entry.role||!entry.preview_assertion||!entry.production_assertion)throw new MigrationTrainError(`migration at position ${index+1} is missing exact identity, role, risk, or assertions`)
    if(seen.has(entry.version))throw new MigrationTrainError(`migration ${entry.version} appears more than once`);seen.add(entry.version)
    if(entry.dependencies.some((v)=>!VERSION.test(v)))throw new MigrationTrainError(`migration ${entry.version} has an invalid dependency`)
    return entry
  })
  for(let i=1;i<normalized.length;i++)if(normalized[i-1].version>=normalized[i].version)throw new MigrationTrainError('train migration list must be strictly version ordered')
  return normalized
}

export function proposeTrain({target,target_identity,base_main_sha,entries}){
  if(!target||!target_identity||!SHA.test(String(base_main_sha??'')))throw new MigrationTrainError('train requires exact target identity and current main SHA')
  const record={schema_version:1,target:String(target),target_identity:String(target_identity),base_main_sha:String(base_main_sha).toLowerCase(),entries:requireExactEntries(entries)}
  const manifest_digest=sha256(canonicalJson(record)),train_id=manifest_digest
  return {...record,manifest_digest,train_id,state:'proposed',generation:1}
}

export function persistProposedTrain(manifest,io){
  const expected=proposeTrain(manifest)
  if(!sameRecord(manifest,expected))throw new MigrationTrainError('proposed train is not the canonical manifest')
  const ref=trainRef(expected),digest=recordDigest(expected)
  if(!io.createImmutable(ref,digest,expected)){
    const prior=io.readImmutable(ref)
    if(prior?.digest!==digest||!sameRecord(prior.record,expected))throw new MigrationTrainError('conflicting immutable proposed record already exists')
  }
  const stored=io.readImmutable(ref)
  if(stored?.digest!==digest||!sameRecord(stored.record,expected))throw new MigrationTrainError('immutable proposed record readback mismatch')
  return expected
}

export function validateTrain(manifest,proof){
  const expected=proposeTrain(manifest)
  if(manifest.state!=='proposed'||manifest.generation!==1||manifest.train_id!==expected.train_id||manifest.manifest_digest!==expected.manifest_digest)throw new MigrationTrainError('train manifest identity, generation, state, or digest is stale')
  if(proof.main_sha!==manifest.base_main_sha)throw new MigrationTrainError('train authorization is stale because current main moved')
  if(proof.target_identity!==manifest.target_identity)throw new MigrationTrainError('train target identity changed')
  const versions=new Set(manifest.entries.map((e)=>e.version)),risks=new Set(manifest.entries.map((e)=>e.risk_class)),roles=new Set(proof.available_roles??[]),ledger=new Set(proof.applied_versions??[]),forbidden=new Set(proof.forbidden_versions??[]),superseded=new Set(proof.superseded_versions??[])
  if(risks.size!==1)throw new MigrationTrainError(`mixed risk classes refuse: ${[...risks].join(', ')}`)
  for(const entry of manifest.entries){
    const live=proof.main_migrations?.[entry.version]
    if(!live||live.file_sha256!==entry.file_sha256||live.source_pr!==entry.source_pr||live.merge_sha!==entry.merge_sha||proof.merge_in_main?.[entry.merge_sha]!==true)throw new MigrationTrainError(`migration ${entry.version} is not exactly merged on current main`)
    if(ledger.has(entry.version))throw new MigrationTrainError(`migration ${entry.version} is already applied on the exact target`)
    if(forbidden.has(entry.version))throw new MigrationTrainError(`migration ${entry.version} is forbidden`)
    if(superseded.has(entry.version))throw new MigrationTrainError(`migration ${entry.version} is superseded`)
    if(!roles.has(entry.role))throw new MigrationTrainError(`migration ${entry.version} requires absent database role ${entry.role}`)
    for(const dependency of entry.dependencies)if(!ledger.has(dependency)&&(!versions.has(dependency)||manifest.entries.findIndex((x)=>x.version===dependency)>=manifest.entries.findIndex((x)=>x.version===entry.version)))throw new MigrationTrainError(`migration ${entry.version} is missing an earlier dependency ${dependency}`)
    const preview=proof.preview_assertions?.[entry.version],production=proof.production_assertions?.[entry.version]
    if(preview?.assertion!==entry.preview_assertion||preview?.result!=='passed'||production?.assertion!==entry.production_assertion||production?.result!=='passed')throw new MigrationTrainError(`migration ${entry.version} lacks exact passing preview/production assertion coverage`)
  }
  return {...manifest,validated:true,risk_class:[...risks][0]}
}

export function transitionTrain(manifest,next,io,{authorization_digest=null,current_main_sha=null,target_identity=null,applied_prefix=[],live_applied_versions=[],live_assertions=null}={}){
  const allowed={proposed:['authorized'],authorized:['dispatched'],dispatched:['closed','failed'],failed:['dispatched'],closed:[]}
  if(!TRAIN_STATES.includes(next)||!allowed[manifest.state]?.includes(next))throw new MigrationTrainError(`train cannot move from ${manifest.state} to ${next}`)
  if(!Number.isSafeInteger(manifest.generation)||manifest.generation<1||!DIGEST.test(String(manifest.train_id??''))||!DIGEST.test(String(manifest.manifest_digest??'')))throw new MigrationTrainError('train lifecycle identity or generation is malformed')
  const expectedManifest=proposeTrain(manifest)
  if(expectedManifest.train_id!==manifest.train_id||expectedManifest.manifest_digest!==manifest.manifest_digest)throw new MigrationTrainError('train lifecycle no longer matches its immutable manifest')
  const predecessorRef=trainRef(manifest),predecessor=io.readImmutable(predecessorRef)
  const runtimeKeys=manifest.state==='proposed'?new Set(['validated','risk_class']):new Set(['validated'])
  const persistedManifest=Object.fromEntries(Object.entries(manifest).filter(([key])=>!runtimeKeys.has(key)))
  const persistedDigest=recordDigest(persistedManifest)
  if(!predecessor||predecessor.digest!==persistedDigest||!sameRecord(predecessor.record,persistedManifest))throw new MigrationTrainError('exact immutable predecessor is missing or changed')
  assertLifecycleChain(persistedManifest,io)
  if(next==='authorized'&&(manifest.validated!==true||!DIGEST.test(String(authorization_digest??''))||current_main_sha!==manifest.base_main_sha||target_identity!==manifest.target_identity))throw new MigrationTrainError('authorization requires a validated manifest, exact current main and target, and policy-evidence digest')
  if(next==='dispatched'&&(current_main_sha!==manifest.base_main_sha||target_identity!==manifest.target_identity))throw new MigrationTrainError('dispatch requires the authorization\'s exact current main and target')
  const exact=manifest.entries.map((e)=>e.version),prefix=[...applied_prefix].map(String)
  const liveVersions=[...live_applied_versions].map(String),trainApplied=exact.filter((version)=>new Set(liveVersions).has(version))
  const exactPrefix=(candidate)=>candidate.length<exact.length&&candidate.every((v,i)=>v===exact[i])
  const sameList=(left,right)=>left.length===right.length&&left.every((value,index)=>value===right[index])
  if(next==='failed'){
    if(target_identity!==manifest.target_identity||current_main_sha!==manifest.base_main_sha||!exactPrefix(prefix)||!sameList(trainApplied,prefix))throw new MigrationTrainError('failure must reconcile the exact proper applied prefix from the live target ledger')
  }
  if(manifest.state==='failed'&&next==='dispatched'){
    const recorded=[...(manifest.applied_prefix??[])].map(String)
    if(target_identity!==manifest.target_identity||current_main_sha!==manifest.base_main_sha||!exactPrefix(recorded)||!sameList(trainApplied,recorded))throw new MigrationTrainError('forward recovery requires the unchanged exact live-ledger applied prefix')
  }
  if(next==='closed'){
    const report=live_assertions
    if(target_identity!==manifest.target_identity||current_main_sha!==manifest.base_main_sha||!sameList(trainApplied,exact)||!report||canonicalJson(Object.keys(report).sort())!==canonicalJson([...exact].sort()))throw new MigrationTrainError('close requires the exact full train applied on the live target and one report per migration')
    for(const entry of manifest.entries){const row=report[entry.version];if(row?.file_sha256!==entry.file_sha256||row?.preview_assertion!==entry.preview_assertion||row?.preview_result!=='passed'||row?.production_assertion!==entry.production_assertion||row?.production_result!=='passed')throw new MigrationTrainError(`close lacks exact live assertion results for migration ${entry.version}`)}
  }
  const clean=Object.fromEntries(Object.entries(manifest).filter(([key])=>key!=='validated'))
  const recovery=manifest.state==='failed'&&next==='dispatched'?{recovery_from_prefix:[...manifest.applied_prefix],remaining_suffix:exact.slice(manifest.applied_prefix.length)}:{}
  const record={...clean,state:next,generation:manifest.generation+1,...(authorization_digest?{authorization_digest}:{}),...(next==='failed'?{applied_prefix:prefix}:{}),...recovery,previous_ref:predecessorRef,previous_digest:persistedDigest}
  const digest=recordDigest(record),ref=trainRef(record)
  if(!io.createImmutable(ref,digest,record)){const prior=io.readImmutable(ref);if(prior?.digest!==digest||!sameRecord(prior.record,record))throw new MigrationTrainError(`conflicting immutable ${next} record already exists`)}
  const stored=io.readImmutable(ref)
  if(stored?.digest!==digest||!sameRecord(stored.record,record))throw new MigrationTrainError(`immutable ${next} record readback mismatch`)
  return record
}
