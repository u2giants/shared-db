import test from "node:test";
import assert from "node:assert/strict";

import {
  PROJECT_REF,
  PROJECT_REF_FILE,
  LINKED_PROJECT_FILE,
  resolveExpectedRef,
  parseProjectRefFile,
  parseLinkedProjectFile,
  evaluateLinkState,
  readOptional,
} from "./check-supabase-link-state.mjs";

// Refs used ONLY as test fixtures. They are shaped like real refs (20 lowercase
// alphanumerics) but are not any real project, so a copy-paste out of this file
// cannot reach a database.
const REF_A = "aaaaaaaaaaaaaaaaaaaa";
const REF_B = "bbbbbbbbbbbbbbbbbbbb";

const json = (ref) => JSON.stringify({ ref, name: "example", organization_id: "x" });

// ---------------------------------------------------------------------------
// THE HEADLINE CASE: the exact 2026-08-07 trap.
// ---------------------------------------------------------------------------

test("THE TRAP: the two link files disagree, and that is an ERROR even when project-ref is the one you expected", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: `${REF_A}\n`, // the file the old documented check read -> "looks fine"
        linkedProjectRaw: json(REF_B), // the file nobody read -> the real target
        expectedRef: REF_A,
      }),
    (err) => {
      // It must fail even though project-ref matches expectedRef exactly, which is
      // precisely the situation that produced a green check over a wrong target.
      assert.match(err.message, /INCONSISTENT/);
      // Both observed values must be named, or the reader cannot see the trap.
      assert.match(err.message, new RegExp(REF_A));
      assert.match(err.message, new RegExp(REF_B));
      assert.match(err.message, new RegExp(PROJECT_REF_FILE.replace(/[.]/g, "\\.")));
      assert.match(err.message, new RegExp(LINKED_PROJECT_FILE.replace(/[.]/g, "\\.")));
      return true;
    }
  );
});

test("the disagreement is caught in the other direction too", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: REF_B,
        linkedProjectRaw: json(REF_A),
        expectedRef: REF_A,
      }),
    /INCONSISTENT/
  );
});

test("the inconsistency error is reported IN PREFERENCE TO a plain expectation mismatch", () => {
  // Both files disagree with each other AND with the expectation. The informative
  // message is the one naming both files; a bare "wrong project" would hide the drift.
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: REF_A,
        linkedProjectRaw: json(REF_B),
        expectedRef: "cccccccccccccccccccc",
      }),
    /INCONSISTENT/
  );
});

// ---------------------------------------------------------------------------
// The happy path is narrow on purpose.
// ---------------------------------------------------------------------------

test("passes ONLY when both files exist, agree, and match the expected ref", () => {
  const result = evaluateLinkState({
    projectRefRaw: `${REF_A}\n`,
    linkedProjectRaw: json(REF_A),
    expectedRef: REF_A,
  });
  assert.deepEqual(result, {
    ref: REF_A,
    projectRefFile: REF_A,
    linkedProjectFile: REF_A,
  });
});

test("surrounding whitespace and a trailing newline do not affect agreement", () => {
  const result = evaluateLinkState({
    projectRefRaw: `  ${REF_A}  \r\n`,
    linkedProjectRaw: `\n  ${json(REF_A)}\n`,
    expectedRef: `  ${REF_A}  `,
  });
  assert.equal(result.ref, REF_A);
});

test("agreeing files that name the WRONG project still fail", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: REF_B,
        linkedProjectRaw: json(REF_B),
        expectedRef: REF_A,
      }),
    (err) => {
      assert.match(err.message, /WRONG PROJECT/);
      assert.match(err.message, new RegExp(REF_B));
      assert.match(err.message, new RegExp(REF_A));
      return true;
    }
  );
});

// ---------------------------------------------------------------------------
// Fail closed. "I could not tell" must never read as "fine".
// ---------------------------------------------------------------------------

test("both files absent is an ERROR, not an implicit pass", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: null,
        linkedProjectRaw: null,
        expectedRef: REF_A,
      }),
    /NOT linked/
  );
});

test("linked-project.json ABSENT is the NORMAL post-`supabase link` state and must PASS", () => {
  // Measured 2026-08-07: `supabase link --project-ref <ref>` writes ONLY project-ref.
  // If this case failed, the check would cry wolf on every freshly linked checkout,
  // and a check that cries wolf is one people learn to skip.
  const result = evaluateLinkState({
    projectRefRaw: `${REF_A}\n`,
    linkedProjectRaw: null,
    expectedRef: REF_A,
  });
  assert.deepEqual(result, {
    ref: REF_A,
    projectRefFile: REF_A,
    linkedProjectFile: null,
  });
});

test("an absent linked-project.json does NOT excuse a project-ref naming the wrong project", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: REF_B,
        linkedProjectRaw: null,
        expectedRef: REF_A,
      }),
    /WRONG PROJECT/
  );
});

test("linked-project.json WITHOUT project-ref is orphaned leftovers, not a link", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: null,
        linkedProjectRaw: json(REF_B),
        expectedRef: REF_A,
      }),
    (err) => {
      assert.match(err.message, /NOT linked/);
      assert.match(err.message, /ORPHANED/);
      // It must name the ref hiding in the leftover file, since that is the value
      // another tool may still act on.
      assert.match(err.message, new RegExp(REF_B));
      assert.match(err.message, new RegExp(PROJECT_REF_FILE.replace(/[.]/g, "\\.")));
      return true;
    }
  );
});

// ---------------------------------------------------------------------------
// The expected ref is REQUIRED and has no default.
// ---------------------------------------------------------------------------

test("the expected ref is required -- undefined, empty and whitespace all fail", () => {
  for (const bad of [undefined, null, "", "   ", "\n"]) {
    assert.throws(() => resolveExpectedRef(bad), /REQUIRED and has no default/);
  }
});

test("a malformed expected ref is rejected rather than coerced", () => {
  for (const bad of [
    "TOOSHORT",
    REF_A.toUpperCase(),
    `${REF_A}x`,
    REF_A.slice(0, 19),
    "aaaa-aaaa-aaaa-aaaaa",
  ]) {
    assert.throws(() => resolveExpectedRef(bad), /20 lowercase letters\/digits/);
  }
});

test("a missing expected ref fails even when the two files agree perfectly", () => {
  assert.throws(
    () =>
      evaluateLinkState({
        projectRefRaw: REF_A,
        linkedProjectRaw: json(REF_A),
        expectedRef: undefined,
      }),
    /REQUIRED and has no default/
  );
});

// ---------------------------------------------------------------------------
// File-level parsing: malformed is an error, never a shrug.
// ---------------------------------------------------------------------------

test("parseProjectRefFile: absent is null, empty is an error", () => {
  assert.equal(parseProjectRefFile(null), null);
  assert.equal(parseProjectRefFile(undefined), null);
  assert.throws(() => parseProjectRefFile("   \n"), /EMPTY/);
});

test("parseProjectRefFile rejects a ref that is not ref-shaped", () => {
  assert.throws(() => parseProjectRefFile("not a ref"), /valid project ref/);
  assert.throws(() => parseProjectRefFile(REF_A.toUpperCase()), /valid project ref/);
});

test("parseLinkedProjectFile: absent is null, empty is an error", () => {
  assert.equal(parseLinkedProjectFile(null), null);
  assert.throws(() => parseLinkedProjectFile(""), /EMPTY/);
});

test("parseLinkedProjectFile rejects unparseable JSON WITHOUT printing its content", () => {
  const secretish = "{ ref: leaked-value-should-not-appear";
  assert.throws(
    () => parseLinkedProjectFile(secretish),
    (err) => {
      assert.match(err.message, /not valid JSON/);
      assert.ok(
        !err.message.includes("leaked-value-should-not-appear"),
        "the file content must never be echoed into an error message"
      );
      return true;
    }
  );
});

test("parseLinkedProjectFile rejects a non-object, a missing ref and a bad ref", () => {
  assert.throws(() => parseLinkedProjectFile("[]"), /JSON object/);
  assert.throws(() => parseLinkedProjectFile("null"), /JSON object/);
  assert.throws(() => parseLinkedProjectFile('"a string"'), /JSON object/);
  assert.throws(() => parseLinkedProjectFile("{}"), /no usable "ref" field/);
  assert.throws(() => parseLinkedProjectFile('{"ref": ""}'), /no usable "ref" field/);
  assert.throws(() => parseLinkedProjectFile('{"ref": 12345}'), /no usable "ref" field/);
  assert.throws(() => parseLinkedProjectFile('{"ref": "SHORT"}'), /valid project ref/);
});

test("parseLinkedProjectFile ignores the other CLI-written fields", () => {
  const ref = parseLinkedProjectFile(
    JSON.stringify({ ref: REF_A, name: "popdam", organization_slug: "zzz", extra: 1 })
  );
  assert.equal(ref, REF_A);
});

// ---------------------------------------------------------------------------
// readOptional: ENOENT is null; every other error propagates.
// ---------------------------------------------------------------------------

test("readOptional maps ENOENT to null", async () => {
  const read = async () => {
    const err = new Error("nope");
    err.code = "ENOENT";
    throw err;
  };
  assert.equal(await readOptional("whatever", read), null);
});

test("readOptional does NOT swallow a permissions error", async () => {
  const read = async () => {
    const err = new Error("denied");
    err.code = "EACCES";
    throw err;
  };
  await assert.rejects(() => readOptional("whatever", read), /denied/);
});

test("readOptional returns the file text unchanged", async () => {
  assert.equal(await readOptional("p", async () => `${REF_A}\n`), `${REF_A}\n`);
});

// ---------------------------------------------------------------------------
// The shared ref pattern.
// ---------------------------------------------------------------------------

test("PROJECT_REF accepts exactly 20 lowercase alphanumerics and nothing else", () => {
  assert.ok(PROJECT_REF.test(REF_A));
  assert.ok(PROJECT_REF.test("rjyboqwcdzcocqgmsyel"));
  assert.ok(!PROJECT_REF.test(""));
  assert.ok(!PROJECT_REF.test("a".repeat(19)));
  assert.ok(!PROJECT_REF.test("a".repeat(21)));
  assert.ok(!PROJECT_REF.test("A".repeat(20)));
  assert.ok(!PROJECT_REF.test(`${"a".repeat(19)}_`));
});

test("no real project ref is hard-coded as a DEFAULT anywhere in the checker", async () => {
  // The refs appear in the incident comment as history. What must never exist is a
  // fallback that supplies one when the caller did not.
  const { readFile } = await import("node:fs/promises");
  const src = await readFile(new URL("./check-supabase-link-state.mjs", import.meta.url), "utf8");
  const code = src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
  assert.ok(!/[a-z0-9]{20}/.test(code.replace(/PROJECT_REF|LINKED_PROJECT_FILE/g, "")),
    "a 20-char ref-shaped literal survives outside the comments -- that would be a default target");
});
