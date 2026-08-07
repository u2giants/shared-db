#!/usr/bin/env node
/**
 * Prove the Supabase CLI link state is HONEST before anyone trusts it.
 *
 * ============================================================================
 * WHY THIS EXISTS -- a real, measured near-miss on 2026-08-07
 * ============================================================================
 * `supabase/.temp/` holds TWO independent records of "which project am I linked
 * to", written at different times by different CLI code paths:
 *
 *     supabase/.temp/project-ref          -> a bare ref, e.g. rjyboqwcdzcocqgmsyel
 *     supabase/.temp/linked-project.json  -> {"ref": "...", "name": ..., ...}
 *
 * On 2026-08-07 they DISAGREED on a working checkout:
 *
 *     project-ref          said  rjyboqwcdzcocqgmsyel   (PREVIEW)
 *     linked-project.json  said  qsllyeztdwjgirsysgai   (PRODUCTION)
 *
 * The safety check documented at the time was `cat supabase/.temp/project-ref`.
 * That check PASSED -- it read the preview file -- while the CLI would have
 * targeted PRODUCTION. A green check that points at the wrong database is worse
 * than no check at all, because it converts caution into false confidence.
 *
 * Neither file is in git (`.gitignore` line 1 excludes `supabase/.temp/`), so
 * the fix CANNOT be a committed file. It has to be a committed CHECK. This is it.
 *
 * ----------------------------------------------------------------------------
 * THE RULE THIS ENFORCES
 * ----------------------------------------------------------------------------
 * Never infer the target from link state. NAME the ref you mean, explicitly, and
 * make the tooling prove link state agrees with it. That is why `expectedRef` is
 * a REQUIRED input with no default: a default would reintroduce exactly the
 * silent-wrong-target failure this file exists to stop.
 *
 * It FAILS CLOSED. A missing `project-ref`, an unparseable file, two files that
 * disagree, or agreement on the WRONG ref are all errors. "I could not tell" is
 * never reported as "fine".
 *
 * ONE DELIBERATE EXCEPTION, measured on 2026-08-07:
 * `supabase link --project-ref <ref>` writes ONLY `project-ref`. It does not
 * create, refresh or delete `linked-project.json` -- that file comes from a
 * DIFFERENT tool (the Supabase editor extension / MCP tooling). That is the root
 * cause of the incident above: the JSON file was stale leftovers pointing at
 * production, and NO amount of re-linking would ever have corrected it.
 * So `linked-project.json` is OPTIONAL here: absent is normal and passes, but if
 * it is present it MUST agree. Failing on its absence would make this check cry
 * wolf on every freshly linked checkout, and a check that cries wolf gets skipped.
 *
 * This file contacts NO database, reads NO credential, and needs NO secret. It is
 * pure text handling so it can run in CI offline (tools-offline-tests.yml).
 *
 * ----------------------------------------------------------------------------
 * USAGE
 * ----------------------------------------------------------------------------
 *   SUPABASE_EXPECTED_PROJECT_REF=rjyboqwcdzcocqgmsyel \
 *     node tools/check-supabase-link-state.mjs
 *
 *   node tools/check-supabase-link-state.mjs --expect-ref=rjyboqwcdzcocqgmsyel
 *
 * `--expect-ref=` overrides the environment variable. Exit 0 means both files
 * exist, agree with each other, and name the ref you asked for. Any other
 * situation exits 1 with an error that names BOTH observed values.
 *
 * NEVER hard-code a project ref in this file. The refs above appear only inside
 * this comment, as the historical record of the incident.
 */

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve as resolvePath, join as joinPath, dirname } from "node:path";

/** A Supabase project ref: exactly 20 lowercase letters/digits. */
export const PROJECT_REF = /^[a-z0-9]{20}$/;

export const PROJECT_REF_FILE = "supabase/.temp/project-ref";
export const LINKED_PROJECT_FILE = "supabase/.temp/linked-project.json";

/**
 * Validate the ref the caller SAYS they mean.
 *
 * Required, with no default, on purpose: a default is indistinguishable from an
 * unset variable at the moment it matters, and it would silently re-enable the
 * failure this file exists to prevent.
 */
export function resolveExpectedRef(raw) {
  const ref = String(raw ?? "").trim();
  if (ref === "") {
    throw new Error(
      "The expected project ref is REQUIRED and has no default. Pass " +
        "--expect-ref=<ref> or set SUPABASE_EXPECTED_PROJECT_REF. Link state is exactly " +
        "what must not be trusted here, so the ref you MEAN has to be stated explicitly."
    );
  }
  if (!PROJECT_REF.test(ref)) {
    throw new Error(
      `The expected project ref must be 20 lowercase letters/digits, got ${JSON.stringify(ref)}.`
    );
  }
  return ref;
}

/**
 * Parse `supabase/.temp/project-ref` (a bare ref, possibly with trailing newline).
 * `null` means the file is absent; that is the caller's decision to interpret.
 */
export function parseProjectRefFile(raw) {
  if (raw === null || raw === undefined) return null;
  const ref = String(raw).trim();
  if (ref === "") {
    throw new Error(
      `${PROJECT_REF_FILE} exists but is EMPTY. A half-written link file is not a link. ` +
        "Re-run `supabase link` naming the project explicitly, or delete supabase/.temp/."
    );
  }
  if (!PROJECT_REF.test(ref)) {
    throw new Error(
      `${PROJECT_REF_FILE} does not contain a valid project ref (20 lowercase ` +
        `letters/digits), got ${JSON.stringify(ref)}.`
    );
  }
  return ref;
}

/**
 * Parse `supabase/.temp/linked-project.json`.
 *
 * A malformed or ref-less JSON file is an ERROR, never a shrug. Treating it as
 * "unknown, carry on" is how the disagreement went unnoticed: the file nobody
 * parsed was the one holding the production ref.
 */
export function parseLinkedProjectFile(raw) {
  if (raw === null || raw === undefined) return null;
  const text = String(raw).trim();
  if (text === "") {
    throw new Error(
      `${LINKED_PROJECT_FILE} exists but is EMPTY. Re-run \`supabase link\` naming the ` +
        "project explicitly, or delete supabase/.temp/."
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(
      `${LINKED_PROJECT_FILE} is not valid JSON. Its content is deliberately NOT printed ` +
        "here. Delete supabase/.temp/ and re-link naming the project explicitly."
    );
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${LINKED_PROJECT_FILE} must contain a JSON object.`);
  }
  const ref = typeof parsed.ref === "string" ? parsed.ref.trim() : "";
  if (ref === "") {
    throw new Error(`${LINKED_PROJECT_FILE} has no usable "ref" field.`);
  }
  if (!PROJECT_REF.test(ref)) {
    throw new Error(
      `${LINKED_PROJECT_FILE} "ref" is not a valid project ref (20 lowercase ` +
        `letters/digits), got ${JSON.stringify(ref)}.`
    );
  }
  return ref;
}

/**
 * THE GATE. Both files must exist, agree with each other, and equal `expectedRef`.
 *
 * Order is load-bearing. The two files are compared to EACH OTHER first, so the
 * error a session sees for the 2026-08-07 state is the informative one -- "these
 * two disagree, here is each value" -- rather than a bare mismatch against the
 * expectation that leaves the second file unmentioned and the trap undiscovered.
 */
export function evaluateLinkState({ projectRefRaw, linkedProjectRaw, expectedRef } = {}) {
  const expected = resolveExpectedRef(expectedRef);
  const fromRefFile = parseProjectRefFile(projectRefRaw);
  const fromJsonFile = parseLinkedProjectFile(linkedProjectRaw);

  // `project-ref` is the file the CLI actually maintains, so its ABSENCE means
  // unlinked. `linked-project.json` alone is not a link -- it is leftovers.
  if (fromRefFile === null) {
    throw new Error(
      `${PROJECT_REF_FILE} does not exist: this checkout is NOT linked` +
        (fromJsonFile === null
          ? ". That is not a pass. Link explicitly, or use a path that names the project " +
            "ref in the request itself (the Management API) instead of relying on link state."
          : `, yet ${LINKED_PROJECT_FILE} survives and names ${fromJsonFile}. That file is ` +
            "ORPHANED state from another tool, not a link. Delete supabase/.temp/.")
    );
  }

  // linked-project.json being ABSENT is NORMAL and is NOT an error. Measured on
  // 2026-08-07: `supabase link --project-ref <ref>` writes ONLY project-ref and
  // never creates or refreshes linked-project.json. The JSON file is written by a
  // DIFFERENT tool (the Supabase editor extension / MCP tooling), which is exactly
  // why the 2026-08-07 pair could disagree: no `supabase link` will ever correct
  // it, so it sits there stale and outranks nothing while looking authoritative.
  //
  // Treating its absence as a failure would make this check cry wolf on every
  // freshly linked checkout, and a check that cries wolf is a check people learn
  // to skip. So: OPTIONAL, but MUST AGREE WHEN PRESENT.
  if (fromJsonFile !== null && fromRefFile !== fromJsonFile) {
    throw new Error(
      "SUPABASE LINK STATE IS INCONSISTENT -- THIS IS THE 2026-08-07 TRAP.\n" +
        `  ${PROJECT_REF_FILE} says      ${fromRefFile}\n` +
        `  ${LINKED_PROJECT_FILE} says  ${fromJsonFile}\n` +
        "Checking only one of these produces a GREEN result while the CLI targets the " +
        "other project. Do not proceed and do not pick a winner by hand: delete " +
        "supabase/.temp/ and re-link naming the project explicitly."
    );
  }

  if (fromRefFile !== expected) {
    throw new Error(
      `WRONG PROJECT: link state names ${fromRefFile}, but the expected project is ` +
        `${expected}. ` +
        (fromJsonFile === null
          ? `${PROJECT_REF_FILE} is the only link file present and it does not agree with YOU, `
          : "Both link files agree with each other and disagree with YOU, ") +
        "so this is a real target mismatch, not file drift. Re-link, or correct the " +
        "expected ref -- do not bypass this check."
    );
  }

  // linkedProjectFile is null when the JSON file is absent, which is the normal
  // post-`supabase link` state. Callers must not treat null as "unknown target".
  return { ref: expected, projectRefFile: fromRefFile, linkedProjectFile: fromJsonFile };
}

/** Read a file, mapping "not found" to null and letting every other error through. */
export async function readOptional(path, read = readFile) {
  try {
    return await read(path, "utf8");
  } catch (err) {
    if (err && err.code === "ENOENT") return null;
    throw err;
  }
}

export function repoRootFrom(moduleUrl) {
  // tools/<file> -> repo root
  return resolvePath(dirname(fileURLToPath(moduleUrl)), "..");
}

async function main() {
  const args = process.argv.slice(2);
  const refArg = args.find((a) => a.startsWith("--expect-ref="));
  const expectedRef = refArg
    ? refArg.slice("--expect-ref=".length)
    : process.env.SUPABASE_EXPECTED_PROJECT_REF;

  const root = repoRootFrom(import.meta.url);
  const result = evaluateLinkState({
    projectRefRaw: await readOptional(joinPath(root, PROJECT_REF_FILE)),
    linkedProjectRaw: await readOptional(joinPath(root, LINKED_PROJECT_FILE)),
    expectedRef,
  });

  console.log(
    `Supabase link state is consistent and matches the expected project: ${result.ref}\n` +
      `  ${PROJECT_REF_FILE}: ${result.projectRefFile}\n` +
      `  ${LINKED_PROJECT_FILE}: ` +
      (result.linkedProjectFile === null
        ? "absent (normal -- `supabase link` does not write this file)"
        : result.linkedProjectFile)
  );
}

function isEntryPoint() {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return resolvePath(fileURLToPath(import.meta.url)) === resolvePath(entry);
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  main().catch((err) => {
    console.error(String(err.message ?? err));
    process.exit(1);
  });
}
