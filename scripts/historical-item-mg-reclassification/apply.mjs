#!/usr/bin/env node
// Step 2: the guarded executor CLI.
//
//   node apply.mjs --manifest <private manifest.json> --target preview|production \
//     --expect-project-ref <ref> --expect-manifest-sha256 <digest> \
//     --backup-out <PRIVATE dir> [--authorization <file>] [--apply]
//
// WITHOUT --apply this is a dry run: it opens a transaction, locks and
// revalidates every candidate row, and ROLLS BACK. Nothing is written.
//
// --apply writes rows. Running it against preview or production requires
// Albert's separate explicit authorization; building and testing this tool did
// not authorize running it. For production an authorization artifact naming the
// exact manifest digest is additionally required by lib/manifest.mjs.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { WRITABLE_FIELDS } from './lib/constants.mjs';
import { manifestDigest } from './lib/manifest.mjs';
import { runBatch } from './lib/execute.mjs';
import { connect, parseArgs } from './lib/pg.mjs';
import { assertLiveIdentity, readLiveIdentity } from './lib/target.mjs';

const FLAGS = [
  'manifest', 'target', 'expect_project_ref', 'expect_manifest_sha256',
  'expect_cluster_id', 'backup_out', 'authorization', 'apply', 'help',
];

/** Capture the exact before-state of every candidate row, for rollback. */
export async function captureBackup(client, manifest, { target, digest, projectRef, cluster }) {
  const ids = manifest.candidates.map((c) => c.item_id_pk);
  const { rows } = await client.query(
    `select item_id_pk, ${WRITABLE_FIELDS.join(', ')} from dflow."itemHeader" `
    + 'where item_id_pk = any($1::int[]) order by item_id_pk',
    [ids],
  );
  const after = new Map(manifest.candidates.map((c) => [c.item_id_pk, c.after]));
  return {
    schema: 'historical-item-mg-reclassification/backup@1',
    target,
    project_ref: projectRef,
    cluster_system_identifier: cluster,
    manifest_sha256: digest,
    captured_at: new Date().toISOString(),
    rows: rows.map((r) => ({
      item_id_pk: Number(r.item_id_pk),
      before: Object.fromEntries(WRITABLE_FIELDS.map((f) => [f, r[f] ?? null])),
      after: after.get(Number(r.item_id_pk)),
    })),
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2), FLAGS);
  if (args.help || !args.manifest || !args.target || !args.backup_out) {
    console.error('usage: apply.mjs --manifest <file> --target preview|production '
      + '--expect-project-ref <ref> --expect-manifest-sha256 <digest> '
      + '--backup-out <private dir> [--authorization <file>] [--apply]');
    process.exit(2);
  }
  const manifest = JSON.parse(readFileSync(resolve(args.manifest), 'utf8'));
  const digest = manifestDigest(manifest);
  if (!args.expect_manifest_sha256) {
    throw new Error('REFUSED: --expect-manifest-sha256 is required; the file name is not approval');
  }
  const authorization = args.authorization
    ? JSON.parse(readFileSync(resolve(args.authorization), 'utf8'))
    : undefined;

  const { client, projectRef } = await connect({
    target: args.target, expectedRef: args.expect_project_ref,
  });
  try {
    const identity = assertLiveIdentity(await readLiveIdentity(client), args.expect_cluster_id);
    console.error(`target proof: project ${projectRef}, database ${identity.database}, `
      + `cluster ${identity.system_identifier}`);

    const backup = await captureBackup(client, manifest, {
      target: args.target, digest, projectRef, cluster: identity.system_identifier,
    });
    const dir = resolve(args.backup_out);
    mkdirSync(dir, { recursive: true });
    const backupPath = join(dir, `backup-${digest.slice(0, 12)}.json`);
    writeFileSync(backupPath, `${JSON.stringify(backup, null, 2)}\n`);
    console.error(`before-state backup written (${backup.rows.length} rows)`);

    const result = await runBatch(client, manifest, {
      target: args.target,
      mode: args.apply ? 'apply' : 'plan',
      expectedDigest: args.expect_manifest_sha256,
      authorization,
    });
    console.log(JSON.stringify({
      mode: result.mode,
      manifest_sha256: result.manifest_sha256,
      attempted: result.attempted,
      to_change: result.to_change.length,
      already_equal: result.already_equal.length,
      drift: result.drift.length,
      drift_reasons: result.drift.reduce((a, d) => {
        a[d.reason] = (a[d.reason] ?? 0) + 1; return a;
      }, {}),
      changed: result.changed,
    }, null, 2));
  } finally {
    await client.end();
  }
}

if (process.argv[1]?.endsWith('apply.mjs')) {
  main().catch((err) => { console.error(String(err.message ?? err)); process.exit(1); });
}
