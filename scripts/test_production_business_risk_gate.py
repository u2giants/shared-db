import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
from argparse import Namespace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from production_business_risk_gate import authored_merge, exact_main, ProvedTarget, tracked_paths_at, PREVIEW_PRODUCER_PATHS, PREVIEW_RUNTIME_DATA_DIRS, PREVIEW_RUNTIME_DATA_EXEMPTIONS, PRODUCTION_PROJECT_REF, RISK_TEXT, PREVIEW_WORKFLOW, RiskGateError, canonical_sha256, classify_sql, decide_business_risk, gh_json, is_pinned_historical_disney_source, load_activation, prove_activation, prove_applied_commit_is_main_line, preview_applied_commit, prove_historical_original_apply_runs, prove_preview, prove_preview_migration_contents, prove_preview_producer_matches_main

PREVIEW_PROJECT_REF = "mvpkijzfmfcxhnzqogzs"
DEAD_PREVIEW_PROJECT_REF = "rjyboqwcdzcocqgmsyel"


class ProductionBusinessRiskGateTests(unittest.TestCase):
    def test_live_owner_comment_read_retries_transient_failure(self):
        responses=iter([
            subprocess.CompletedProcess([],1,"","HTTP 503: unavailable"),
            subprocess.CompletedProcess([],0,'{"author_association":"OWNER"}',""),
        ])
        sleeps=[]
        result=gh_json("repos/u2giants/shared-db/issues/comments/7",
            runner=lambda *a,**k: next(responses),sleep=sleeps.append)
        self.assertEqual(result,{"author_association":"OWNER"})
        self.assertEqual(sleeps,[1])

    def test_non_comment_evidence_read_never_retries(self):
        calls=[]
        def runner(*args,**kwargs):
            calls.append(1); return subprocess.CompletedProcess([],1,"","HTTP 503: unavailable")
        with self.assertRaisesRegex(RiskGateError,"HTTP 503"):
            gh_json("repos/u2giants/shared-db/pulls/1108",runner=runner,
                sleep=lambda _: self.fail("non-comment read slept"))
        self.assertEqual(len(calls),1)

    def test_live_owner_comment_permanent_absence_never_retries(self):
        calls=[]
        def runner(*args,**kwargs):
            calls.append(1); return subprocess.CompletedProcess([],1,"","HTTP 404: Not Found")
        with self.assertRaisesRegex(RiskGateError,"HTTP 404"):
            gh_json("repos/u2giants/shared-db/issues/comments/7",runner=runner,
                sleep=lambda _: self.fail("permanent absence slept"))
        self.assertEqual(len(calls),1)

    def atomic_preview_fixture(self):
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        migrations = root / "supabase/migrations"
        migrations.mkdir(parents=True)
        config = root / "config"
        config.mkdir()
        version = "20260816110750"
        filename = migrations / f"{version}_safe_forward.sql"
        filename.write_text("lock table plm.bridge in share mode;\n", encoding="utf-8")
        digest = canonical_sha256(filename)
        (config / "atomic-migration-allowlist.json").write_text(json.dumps({
            "schema_version": 1,
            "migrations": {version: {"sha256": digest, "targets": ["preview", "production"]}},
        }), encoding="utf-8")
        preflight = f"ATOMIC PREFLIGHT OK: target=preview version={version} sha256={digest} statements=8"
        texts = {
            "preview-dry-run.txt": preflight + "\n",
            "preview-apply.txt": preflight + "\n" + f"ATOMIC APPLY OK: target=preview version={version} ledger_row=1 statements=8\n",
            "migration-content-manifest.json": json.dumps({version: digest}),
        }
        return temp, root, version, digest, texts

    def test_atomic_preview_proof_binds_version_hash_manifest_apply_and_ledger_delta(self):
        temp, root, version, _, texts = self.atomic_preview_fixture()
        with temp:
            prove_preview_migration_contents(
                texts=texts, allowlist=[version], repo_root=root,
                before_versions={"20260801000000"},
                after_versions={"20260801000000", version}, historical=False,
            )

    def test_atomic_preview_proof_rejects_wrong_version_hash_filename_and_incomplete_proof(self):
        mutations = {
            "wrong version": lambda t, v, d: t.__setitem__("preview-apply.txt", t["preview-apply.txt"].replace(v, "20260816110751")),
            "wrong hash": lambda t, v, d: t.__setitem__("preview-dry-run.txt", t["preview-dry-run.txt"].replace(d, "f" * 64)),
            "wrong manifest": lambda t, v, d: t.__setitem__("migration-content-manifest.json", json.dumps({v: "e" * 64})),
            "missing apply": lambda t, v, d: t.__setitem__("preview-apply.txt", t["preview-apply.txt"].splitlines()[0] + "\n"),
            "forged extra line": lambda t, v, d: t.__setitem__("preview-dry-run.txt", t["preview-dry-run.txt"] + "trust me\n"),
        }
        for name, mutate in mutations.items():
            temp, root, version, digest, texts = self.atomic_preview_fixture()
            with self.subTest(name=name), temp, self.assertRaises(RiskGateError):
                mutate(texts, version, digest)
                prove_preview_migration_contents(
                    texts=texts, allowlist=[version], repo_root=root,
                    before_versions=set(), after_versions={version}, historical=False,
                )

    def test_legacy_preview_proof_still_rejects_wrong_filename(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            migrations = root / "supabase/migrations"
            migrations.mkdir(parents=True)
            (root / "config").mkdir()
            (root / "config/atomic-migration-allowlist.json").write_text(
                '{"schema_version":1,"migrations":{}}', encoding="utf-8"
            )
            version = "20260814000000"
            (migrations / f"{version}_exact.sql").write_text("select 1;", encoding="utf-8")
            texts = {
                "preview-dry-run.txt": f"Applying migration {version}_wrong.sql...",
                "preview-apply.txt": f"Applying migration {version}_wrong.sql...",
            }
            with self.assertRaisesRegex(RiskGateError, "exact migration"):
                prove_preview_migration_contents(
                    texts=texts, allowlist=[version], repo_root=root,
                    before_versions=set(), after_versions={version}, historical=False,
                )

    def plain_preview_fixture(self, body="select 1;\n"):
        """A NON-atomic migration plus a rehearsal manifest that matches its bytes."""
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        migrations = root / "supabase/migrations"
        migrations.mkdir(parents=True)
        (root / "config").mkdir()
        (root / "config/atomic-migration-allowlist.json").write_text(
            '{"schema_version":1,"migrations":{}}', encoding="utf-8"
        )
        version = "20260814000000"
        filename = migrations / f"{version}_exact.sql"
        filename.write_bytes(body.encode("utf-8"))
        digest = hashlib.sha256(filename.read_bytes()).hexdigest()
        texts = {
            "preview-dry-run.txt": f"Applying migration {version}_exact.sql...",
            "preview-apply.txt": f"Applying migration {version}_exact.sql...",
            "migration-content-manifest.json": json.dumps({version: digest}),
        }
        return temp, root, version, digest, texts

    def test_types_only_follow_up_commit_does_not_invalidate_a_matching_rehearsal(self):
        """The exact regression this change exists for.

        A rehearsal ran, then a generated-types commit moved the PR head. No SQL
        moved, so the rehearsal is still true and must be accepted.
        """
        temp, root, version, _, texts = self.plain_preview_fixture()
        with temp:
            prove_preview_migration_contents(
                texts=texts, allowlist=[version], repo_root=root,
                before_versions={"20260801000000"},
                after_versions={"20260801000000", version}, historical=False,
            )

    def test_same_filename_with_different_bytes_on_main_is_rejected(self):
        """The hole the old filename-only check left open on this path."""
        temp, root, version, _, texts = self.plain_preview_fixture()
        with temp:
            rewritten = root / f"supabase/migrations/{version}_exact.sql"
            rewritten.write_bytes(b"drop table plm.item;\n")
            with self.assertRaisesRegex(RiskGateError, "different bytes than exact main"):
                prove_preview_migration_contents(
                    texts=texts, allowlist=[version], repo_root=root,
                    before_versions=set(), after_versions={version}, historical=False,
                )

    def test_non_atomic_proof_requires_a_usable_content_manifest(self):
        for name, mutate in {
            "missing manifest": lambda t: t.pop("migration-content-manifest.json"),
            "manifest not an object": lambda t: t.__setitem__("migration-content-manifest.json", "[]"),
            "manifest missing version": lambda t: t.__setitem__("migration-content-manifest.json", "{}"),
            "manifest digest malformed": lambda t: t.__setitem__(
                "migration-content-manifest.json", json.dumps({"20260814000000": "nope"})
            ),
        }.items():
            temp, root, version, _, texts = self.plain_preview_fixture()
            with self.subTest(name=name), temp, self.assertRaises(RiskGateError):
                mutate(texts)
                prove_preview_migration_contents(
                    texts=texts, allowlist=[version], repo_root=root,
                    before_versions=set(), after_versions={version}, historical=False,
                )

    def test_crlf_migration_still_matches_its_raw_byte_manifest(self):
        """canonical_sha256 normalises CRLF; the manifest does not.

        Comparing the two would reject every CRLF migration on a Windows-authored
        branch, so the gate must digest raw bytes on both sides.
        """
        temp, root, version, _, texts = self.plain_preview_fixture(body="select 1;\r\n")
        with temp:
            prove_preview_migration_contents(
                texts=texts, allowlist=[version], repo_root=root,
                before_versions=set(), after_versions={version}, historical=False,
            )

    def apply_artifact(self, commit, digest="sha256:" + "d" * 64, artifact_id=9, run_id=7):
        return {
            "id": artifact_id, "name": f"preview-migration-apply-{commit}",
            "digest": digest, "expired": False, "workflow_run": {"id": run_id},
        }

    def prove_preview_args(self, **overrides):
        args = dict(
            run_id=7, digest="sha256:" + "c" * 64, pr_head="a" * 40, main_sha="d" * 40,
            source_pr=1, allowlist=["20260814000000"],
            preview_project_ref=PREVIEW_PROJECT_REF, merge_commit_sha="b" * 40,
            repo_root=Path.cwd(),
        )
        args.update(overrides)
        return args

    def test_rehearsal_borrowed_from_another_pull_request_is_rejected(self):
        """Neither a commit of the source PR, nor a commit exact main contains."""
        foreign = "f" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": foreign, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        api = self.preview_api(
            run, [{"sha": "1" * 40}], {}, [self.apply_artifact(foreign)],
            # A rehearsal from an unrelated branch: main does not contain it.
            compare={"status": "diverged", "ahead_by": 2, "behind_by": 3},
        )
        with self.assertRaisesRegex(RiskGateError, "not contained in the history of exact main"):
            prove_preview(
                **self.prove_preview_args(api=api),
                downloader=lambda *_: self.fail("foreign rehearsal must not download"),
            )

    def test_unreadable_source_pr_commits_fail_closed(self):
        foreign = "f" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": foreign, "path": ".github/workflows/shared-supabase-migrations.yml",
        }

        def api(endpoint):
            if endpoint.endswith("commits?per_page=100"):
                raise RuntimeError("GitHub 503")
            if endpoint.endswith("artifacts?per_page=100"):
                return {"artifacts": [self.apply_artifact(foreign)]}
            return run

        with self.assertRaisesRegex(RiskGateError, "unreadable"):
            prove_preview(
                **self.prove_preview_args(api=api),
                downloader=lambda *_: self.fail("must not download"),
            )

    def preview_api(self, run, commits, blobs, artifacts=None, compare=None, seen=None):
        """Fake API covering run, PR commits, producer blobs, trees, artifacts, compare.

        THE TREE AND THE BLOBS COME FROM ONE SOURCE. `blobs` is keyed by
        (path, ref), so a path a test did not state for a ref is absent from
        that ref's tree AND raises from `/contents/`. A helper whose tree and
        whose blob reads could disagree is a helper that cannot express the
        repository (#1213 round 7, finding 1).
        """
        def api(endpoint):
            if seen is not None:
                seen.append(endpoint)
            if endpoint.endswith("commits?per_page=100"):
                return commits
            if "/git/trees/" in endpoint:
                ref = endpoint.split("/git/trees/", 1)[1].split("?")[0]
                return {"truncated": False,
                        "tree": [{"path": p} for (p, r) in blobs if r == ref]}
            if "/compare/" in endpoint:
                if compare is None:
                    raise RuntimeError("compare not stubbed")
                return compare
            if "/contents/" in endpoint:
                path, ref = endpoint.split("/contents/", 1)[1].split("?ref=")
                if (path, ref) in blobs:
                    return {"sha": blobs[(path, ref)]}
                raise RuntimeError("no such content")
            if endpoint.endswith("artifacts?per_page=100"):
                return {"artifacts": artifacts or []}
            return run
        return api

    def test_doctored_producer_commit_cannot_self_attest_a_rehearsal(self):
        """The forgery the exact-head rule used to prevent.

        A branch author pushes C1 carrying a doctored preview workflow that
        fabricates the ledger texts, apply logs and content manifest, dispatches
        preview at C1, then pushes C2 restoring the honest file. The reviewed net
        diff is clean and C1 is a real commit of the PR, so provenance alone
        accepts it. Only pinning the producing code to exact main refuses it.
        """
        c1, head, main = "1" * 40, "2" * 40, "3" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": c1, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        blobs = {}
        for path in PREVIEW_PRODUCER_PATHS:
            blobs[(path, main)] = "honest-" + path
            blobs[(path, c1)] = "honest-" + path
        # C1 carries a doctored workflow; everything else is identical.
        blobs[(PREVIEW_WORKFLOW, c1)] = "doctored-workflow"

        with self.assertRaisesRegex(RiskGateError, "different .* than exact main"):
            prove_preview(
                **self.prove_preview_args(
                    pr_head=head, main_sha=main,
                    api=self.preview_api(
                        run, [{"sha": c1}, {"sha": head}], blobs, [self.apply_artifact(c1)]
                    ),
                ),
                downloader=lambda *_: self.fail("doctored producer must not download"),
            )

    def test_honest_earlier_commit_with_matching_producer_is_accepted_to_download(self):
        """The legitimate case: a types-only follow-up moved the head.

        The rehearsal ran at an earlier commit whose producing code matches exact
        main, so it must survive provenance and reach artifact checking. Proven by
        the failure being the DIGEST check, which is strictly later.
        """
        c1, head, main = "1" * 40, "2" * 40, "3" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": c1, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        blobs = {}
        for path in PREVIEW_PRODUCER_PATHS:
            blobs[(path, main)] = "honest-" + path
            blobs[(path, c1)] = "honest-" + path
        with self.assertRaisesRegex(RiskGateError, "pinned digest"):
            prove_preview(
                **self.prove_preview_args(
                    pr_head=head, main_sha=main,
                    api=self.preview_api(
                        run, [{"sha": c1}, {"sha": head}], blobs, [self.apply_artifact(c1)]
                    ),
                ),
                downloader=lambda *_: self.fail("digest mismatch must not download"),
            )

    def test_unreadable_producer_file_fails_closed(self):
        """A producer file that BOTH trees list but GitHub will not hand over.

        Absence is now proved from the tree, so this test states a file that is
        present on both sides and unreadable anyway. Skipping it would be
        exactly the fail-open the producer pin exists to prevent.
        """
        c1, head, main = "1" * 40, "2" * 40, "3" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": c1, "path": ".github/workflows/shared-supabase-migrations.yml",
        }

        def api(endpoint):
            if endpoint.endswith("artifacts?per_page=100"):
                return {"artifacts": [self.apply_artifact(c1)]}
            if endpoint.endswith("commits?per_page=100"):
                return [{"sha": c1}]
            if "/git/trees/" in endpoint:
                return {"truncated": False,
                        "tree": [{"path": p} for p in PREVIEW_PRODUCER_PATHS]}
            if "/contents/" in endpoint:
                raise RuntimeError("GitHub 500")
            return run

        with self.assertRaisesRegex(RiskGateError, "is unreadable at"):
            prove_preview(
                **self.prove_preview_args(pr_head=head, main_sha=main, api=api),
                downloader=lambda *_: self.fail("must not download"),
            )

    def test_an_unreadable_or_truncated_tree_fails_closed(self):
        """Absence must be a FACT, never an inference from a failed read.

        If the tree read itself fails, or GitHub truncates the listing, a path
        missing from what came back is not evidence that the commit lacks it.
        Either way the gate refuses rather than skipping the comparison.
        """
        ref, main = "1" * 40, "3" * 40
        with self.assertRaisesRegex(RiskGateError, "file tree of .* is unreadable"):
            tracked_paths_at(ref, lambda endpoint: (_ for _ in ()).throw(RuntimeError("503")))
        with self.assertRaisesRegex(RiskGateError, "file tree of .* is unreadable"):
            tracked_paths_at(ref, lambda endpoint: {"tree": "not-a-list"})
        with self.assertRaisesRegex(RiskGateError, "truncated"):
            tracked_paths_at(ref, lambda endpoint: {"truncated": True, "tree": []})
        self.assertEqual(
            tracked_paths_at(main, lambda endpoint: {"truncated": False,
                                                     "tree": [{"path": "a"}, {"nope": 1}]}),
            frozenset({"a"}),
        )

    # ------------------------------------------------------------------
    # POST-MERGE REHEARSAL PROVENANCE AND INSTANCE BINDING (#1208)
    # ------------------------------------------------------------------
    def test_compare_url_argument_order_is_asserted(self):
        """PR #1194 review point 3.

        The old stub never inspected the compare URL, so swapping the arguments
        left every provenance test green while inverting the meaning of the
        check in production. This test reads the URL.
        """
        applied, main = "1" * 40, "3" * 40
        seen = []
        prove_applied_commit_is_main_line(
            applied, main,
            self.preview_api({}, [], {}, [], compare={"status": "ahead", "behind_by": 0}, seen=seen),
        )
        self.assertEqual(seen, [f"repos/u2giants/shared-db/compare/{applied}...{main}"])

    def test_descendant_of_main_is_refused(self):
        """Inverting the compare arguments would make this pass. It must not.

        A commit that is a DESCENDANT of main is unmerged code. Compared in the
        correct order it reports `behind`, never `ahead`.
        """
        with self.assertRaisesRegex(RiskGateError, "not contained in the history of exact main"):
            prove_applied_commit_is_main_line(
                "1" * 40, "3" * 40,
                self.preview_api({}, [], {}, [], compare={"status": "behind", "behind_by": 0}),
            )

    def test_main_line_ancestry_accepts_ahead_and_identical_only_at_behind_zero(self):
        for status in ("ahead", "identical"):
            with self.subTest(status=status):
                prove_applied_commit_is_main_line(
                    "1" * 40, "3" * 40,
                    self.preview_api({}, [], {}, [], compare={"status": status, "behind_by": 0}),
                )
        for compare in (
            {"status": "ahead", "behind_by": 2},
            {"status": "diverged", "behind_by": 0},
            {"status": "ahead"},
            None,
            "not-an-object",
        ):
            with self.subTest(compare=compare), self.assertRaisesRegex(RiskGateError, "unreadable|not contained"):
                prove_applied_commit_is_main_line(
                    "1" * 40, "3" * 40, lambda _e, c=compare: c,
                )

    def test_unreadable_ancestry_fails_closed(self):
        def api(_endpoint):
            raise RuntimeError("GitHub 503")

        with self.assertRaisesRegex(RiskGateError, "ancestry is unreadable"):
            prove_applied_commit_is_main_line("1" * 40, "3" * 40, api)

    def test_applied_commit_comes_from_the_artifact_name_not_the_run_head(self):
        """PR #1194 review point 1.

        A post-merge rehearsal dispatched with `--ref main` has a run head that
        is the workflow-file ref. The commit it actually checked out and applied
        from is the one in the artifact name.
        """
        applied = "7" * 40
        artifact, commit = preview_applied_commit(
            {"artifacts": [self.apply_artifact(applied)]}, 7
        )
        self.assertEqual(commit, applied)
        self.assertEqual(artifact["id"], 9)

    def test_missing_or_ambiguous_apply_artifact_fails_closed(self):
        for label, payload in (
            ("none", {"artifacts": []}),
            ("dry-run only", {"artifacts": [{"name": "preview-migration-dry-run-" + "7" * 40}]}),
            ("two", {"artifacts": [self.apply_artifact("7" * 40), self.apply_artifact("8" * 40, artifact_id=10)]}),
            ("unreadable", {"artifacts": "nope"}),
        ):
            with self.subTest(label), self.assertRaisesRegex(RiskGateError, "unreadable|exactly one preview-migration-apply"):
                preview_applied_commit(payload, 7)

    def preview_evidence_zip(self, path, version, manifest_digest, instance):
        ledger_before = json.dumps([{"remote": "20260801000000"}])
        ledger_after = json.dumps([{"remote": "20260801000000"}, {"remote": version}])
        payload = {
            "preview-ledger-before.txt": ledger_before,
            "preview-ledger-after.txt": ledger_after,
            "preview-dry-run.txt": f"Applying migration {version}_exact.sql...",
            "preview-apply.txt": f"Applying migration {version}_exact.sql...",
            "migration-content-manifest.json": json.dumps({version: manifest_digest}),
        }
        if instance is not None:
            payload["preview-instance.json"] = json.dumps(instance)
        with zipfile.ZipFile(path, "w") as archive:
            for name, text in payload.items():
                archive.writestr(name, text)
        return "sha256:" + hashlib.sha256(Path(path).read_bytes()).hexdigest()

    def run_full_prove_preview(
        self, *, instance, applied=None, main=None, preview_ref=PREVIEW_PROJECT_REF,
        run_head=None, source_pr=1, merge_commit_sha="b" * 40,
    ):
        """End to end through download, so the instance binding is really read."""
        applied = applied or "1" * 40
        main = main or "3" * 40
        # The real post-merge dispatch is `--ref main`, so the workflow that
        # EXECUTES is main's own. Tests that forge it override this.
        run_head = run_head or main
        temp, root, version, digest, _ = self.plain_preview_fixture()
        with temp:
            zip_dir = tempfile.TemporaryDirectory()
            with zip_dir:
                zip_path = Path(zip_dir.name, "evidence.zip")
                artifact_digest = self.preview_evidence_zip(zip_path, version, digest, instance)
                blobs = {}
                for path in PREVIEW_PRODUCER_PATHS:
                    blobs[(path, main)] = "honest-" + path
                    blobs[(path, applied)] = "honest-" + path
                    blobs.setdefault((path, run_head), "honest-" + path)
                run = {
                    "status": "completed", "conclusion": "success",
                    "event": "workflow_dispatch", "head_sha": run_head,
                    "path": ".github/workflows/shared-supabase-migrations.yml",
                }
                api = self.preview_api(
                    run, [{"sha": "a" * 40}], blobs,
                    [self.apply_artifact(applied, digest=artifact_digest)],
                    compare={"status": "ahead", "behind_by": 0},
                )
                prove_preview(
                    run_id=7, digest=artifact_digest, pr_head="a" * 40, main_sha=main,
                    source_pr=source_pr, allowlist=[version], preview_project_ref=preview_ref,
                    merge_commit_sha=merge_commit_sha, api=api, repo_root=root,
                    downloader=lambda _id, dest: Path(dest).write_bytes(zip_path.read_bytes()),
                )

    def honest_instance(self, applied="1" * 40, project_ref=PREVIEW_PROJECT_REF):
        return {
            "schema": "shared-db-preview-instance-binding/v1",
            "rehearsalMode": "merged-main-rehearsal",
            "appliedCommit": applied,
            "previewProjectRef": project_ref,
            "runId": 7,
            "allowlist": ["20260814000000"],
            "sourcePr": 1,
            "mergeCommitSha": "b" * 40,
        }

    def test_post_merge_main_line_rehearsal_is_accepted_end_to_end(self):
        """The whole point of #1208: a merged, main-line rehearsal promotes."""
        self.run_full_prove_preview(instance=self.honest_instance())

    def test_forged_dispatch_ref_cannot_fabricate_a_main_line_rehearsal(self):
        """#1213 review, finding 1. The forge the artifact-name pin alone allowed.

        An attacker pushes branch `evil` whose workflow checks out current main
        (so `git rev-parse HEAD` IS main), skips the apply, hand-writes matching
        ledgers, apply log, content manifest and preview-instance.json, and
        uploads them as `preview-migration-apply-<main-sha>`. They then dispatch
        the workflow with `--ref evil`.

        Everything INSIDE the artifact is consistent, and the applied commit
        equals main, so a pin aimed only at the artifact name compares nothing
        and lets it through. Production would then apply for real versions that
        never touched preview.

        Only `run["head_sha"]` -- the ref GitHub read the workflow FILE from,
        which no part of the artifact can restate -- exposes it.
        """
        main, evil = "3" * 40, "e" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": evil, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        blobs = {}
        for path in PREVIEW_PRODUCER_PATHS:
            blobs[(path, main)] = "honest-" + path
            blobs[(path, evil)] = "honest-" + path
        # The one file the forger had to change: the workflow that runs.
        blobs[(PREVIEW_WORKFLOW, evil)] = "doctored-workflow"
        digest = "sha256:" + "c" * 64
        with self.assertRaisesRegex(RiskGateError, "different .* than exact main"):
            prove_preview(
                **self.prove_preview_args(
                    pr_head="a" * 40, main_sha=main,
                    api=self.preview_api(
                        run, [{"sha": "a" * 40}], blobs,
                        # Named after main, and the digest MATCHES, so nothing
                        # later in the gate would have stopped it either.
                        [self.apply_artifact(main, digest=digest)],
                        compare={"status": "identical", "behind_by": 0},
                    ),
                ),
                downloader=lambda *_: self.fail("forged dispatch ref must not reach download"),
            )

    def test_run_without_a_readable_head_sha_fails_closed(self):
        main = "3" * 40
        for head in (None, "", "not-a-sha", 123):
            run = {
                "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
                "head_sha": head, "path": ".github/workflows/shared-supabase-migrations.yml",
            }
            with self.subTest(head=head), self.assertRaisesRegex(
                RiskGateError, "commit whose workflow executed"
            ):
                prove_preview(
                    **self.prove_preview_args(
                        pr_head="a" * 40, main_sha=main,
                        api=self.preview_api(
                            run, [{"sha": "a" * 40}], {}, [self.apply_artifact(main)],
                            compare={"status": "identical", "behind_by": 0},
                        ),
                    ),
                    downloader=lambda *_: self.fail("must not download"),
                )

    def test_rehearsal_of_another_merged_pull_request_is_refused(self):
        """#1213 review, finding 2. `sourcePr` was written but never read."""
        instance = self.honest_instance()
        instance["sourcePr"] = 999
        with self.assertRaisesRegex(ValueError, "not the pull request being promoted"):
            self.run_full_prove_preview(instance=instance, source_pr=1)

    def test_rehearsal_naming_another_merge_commit_is_refused(self):
        instance = self.honest_instance()
        instance["mergeCommitSha"] = "f" * 40
        with self.assertRaisesRegex(ValueError, "not the merge commit"):
            self.run_full_prove_preview(instance=instance, merge_commit_sha="b" * 40)

    def test_merged_main_rehearsal_missing_its_pull_request_fields_is_refused(self):
        for field in ("sourcePr", "mergeCommitSha"):
            instance = self.honest_instance()
            del instance[field]
            with self.subTest(field=field), self.assertRaisesRegex(
                ValueError, "not the pull request being promoted|not the merge commit"
            ):
                self.run_full_prove_preview(instance=instance)

    def test_preview_evidence_without_an_instance_binding_is_refused(self):
        """PR #1194 review point 4. Deleting the binding must break this."""
        with self.assertRaisesRegex(ValueError, "carries no instance binding"):
            self.run_full_prove_preview(instance=None)

    def test_rebuilt_preview_cannot_inherit_the_deleted_previews_proof(self):
        """A rehearsal against rjyboqwcdzcocqgmsyel is not proof about mvpkijzfmfcxhnzqogzs."""
        with self.assertRaisesRegex(ValueError, "never inherits the proof"):
            self.run_full_prove_preview(
                instance=self.honest_instance(project_ref=DEAD_PREVIEW_PROJECT_REF)
            )

    def test_instance_binding_must_name_the_commit_in_the_artifact_name(self):
        with self.assertRaisesRegex(ValueError, "names applied commit"):
            self.run_full_prove_preview(instance=self.honest_instance(applied="c" * 40))

    def test_expected_preview_ref_is_never_defaulted_and_never_production(self):
        with self.assertRaisesRegex(ValueError, "never treated as a default"):
            self.run_full_prove_preview(instance=self.honest_instance(), preview_ref="")
        with self.assertRaisesRegex(ValueError, "is the PRODUCTION project ref"):
            self.run_full_prove_preview(
                instance=self.honest_instance(project_ref=PRODUCTION_PROJECT_REF),
                preview_ref=PRODUCTION_PROJECT_REF,
            )

    def test_instance_binding_writer_is_a_pinned_preview_producer(self):
        self.assertIn("scripts/preview_instance_binding.py", PREVIEW_PRODUCER_PATHS)

    PREVIEW_JOB_EXCLUSIONS = (
        # These run ONLY in the production-apply jobs, which check out exact main
        # and prove HEAD == origin/main before executing. They are not part of
        # the preview evidence-producing surface.
        "scripts/production_business_risk_gate.py",
        "scripts/production_apply_review_evidence.py",
        "scripts/production_catalog_verification.py",
        # Validate-only job, which produces no evidence.
        # Validate-only job. It produces no evidence, runs on a separate runner,
        # and a forged artifact under the preview name would collide with the
        # preview job's upload and fail the run. Confirmed by independent review.
        "scripts/check-sql.sh",
        "scripts/check-sql.test.mjs",
        # Invoked only by check-sql.sh, so validate-only for the same reason.
        "scripts/historical-migration-restorations.mjs",
    )

    def preview_job_text(self):
        """Just the preview job, so validate-only steps cannot mask a real gap."""
        workflow = (Path(__file__).resolve().parents[1] / PREVIEW_WORKFLOW).read_text(encoding="utf-8")
        start = workflow.index("\n  preview:")
        rest = workflow[start + 1:]
        nxt = re.search(r"\n  [a-zA-Z][\w-]*:\n", rest)
        return rest[: nxt.start()] if nxt else rest

    @staticmethod
    def scripts_invoked_on(line, roots):
        """Repo paths invoked on ONE line by node/python/bash.

        Line-at-a-time on purpose: it keeps the pattern free of newline handling
        and still catches `node --test x`, `python -m y`, quoted paths, and
        `$GITHUB_WORKSPACE/`-prefixed paths, which are the shapes that previously
        slipped past a stricter pattern.
        """
        interpreted = re.search(r"\b(?:node|python|python3|bash|sh|source)\b", line)
        # child_process spawns name the script as a plain string argument, with
        # the interpreter supplied as process.execPath rather than by name.
        spawned = re.search(r"\b(?:execFileSync|execSync|spawnSync|spawn|execFile)\b", line)
        if not interpreted and not spawned:
            return []
        return [m.rstrip(".") for m in re.findall(rf"({roots}/[A-Za-z0-9_.-]+)", line)]

    @staticmethod
    def local_imports(root, body):
        """Sibling modules a body pulls in, for BOTH languages.

        JS was covered from the start. Python was not, and the preview job's
        heredocs already use `from production_migration_guard import ...`. That
        was covered only by coincidence -- the same module happens to be invoked
        by name elsewhere -- so a future helper imported but never invoked would
        have executed unpinned with this test green. That is precisely the defect
        class that reopened the forgery path twice.
        """
        found = [f"scripts/{name}" for name in re.findall(r"from\s+['\"]\./([A-Za-z0-9_.-]+)['\"]", body)]
        for name in re.findall(r"^\s*(?:from|import)\s+([A-Za-z_][A-Za-z0-9_]*)", body, re.M):
            if (root / "scripts" / f"{name}.py").is_file():
                found.append(f"scripts/{name}.py")
        return found

    def executed_closure(self):
        """Every repo script the preview job can execute, including imports.

        Enumerating this by hand is what failed twice: the forgery path was
        reopened at hop two and again at hop three, because a pinned entry point
        statically imports another module whose body runs first. So the closure is
        WALKED, not listed. Invocation shapes are matched loosely on purpose --
        `node --test x`, `python -m y`, and quoted/`$GITHUB_WORKSPACE`-prefixed
        paths must all be seen.
        """
        root = Path(__file__).resolve().parents[1]
        text = self.preview_job_text()
        found = set()
        for line in text.splitlines():
            found.update(self.scripts_invoked_on(line, r"(?:scripts|config)"))
        seen, queue = set(), list(found)
        while queue:
            rel = queue.pop()
            if rel in seen:
                continue
            seen.add(rel)
            path = root / rel
            if not path.is_file():
                continue
            body = path.read_text(encoding="utf-8", errors="ignore")
            queue.extend(self.local_imports(root, body))
            for line in body.splitlines():
                queue.extend(self.scripts_invoked_on(line, "scripts"))
        # Heredocs in the workflow import sibling modules directly rather than
        # invoking them, so the job text is walked for imports too.
        queue.extend(self.local_imports(root, text))
        while queue:
            rel = queue.pop()
            if rel not in seen:
                seen.add(rel)
        return seen

    def test_preview_producer_paths_cover_the_whole_executed_closure(self):
        """The list must not be able to fall silently behind reality.

        Independent review reopened the forgery path twice here: once because a
        script that runs before evidence production was unpinned, and once because
        a PINNED script imported an unpinned one. Anything executing at the
        dispatched ref can rewrite the workspace copies of the pinned files, and
        the gate compares COMMITTED blobs, so it cannot see that. One unpinned
        executed file breaks custody for every pinned one.

        So this walks the closure instead of trusting a hand-written list.
        """
        closure = self.executed_closure()
        self.assertIn("scripts/manage-migration-author-lanes.mjs", closure,
                      "closure walk missed a known preview-job script; the parser has rotted")
        self.assertIn("scripts/check-pr-object-collisions.mjs", closure,
                      "closure walk did not follow imports; that is the hop-three defect")
        # The exclusion list is a hand-written bypass of the walk, so its premise
        # must itself be checked. Every exclusion claims "this does not run in the
        # preview job". If one ever does, the walk would stay green while the
        # script stayed unpinned -- reopening the exact forgery path this test
        # exists to close. Assert the premise instead of trusting the comment.
        job_text = self.preview_job_text()
        for excluded in self.PREVIEW_JOB_EXCLUSIONS:
            for line in job_text.splitlines():
                self.assertNotIn(
                    excluded, self.scripts_invoked_on(line, "scripts"),
                    f"{excluded} is excluded as not-preview-job, but the preview job "
                    f"now invokes it; pin it in PREVIEW_PRODUCER_PATHS instead",
                )
        unpinned = sorted(closure - set(PREVIEW_PRODUCER_PATHS) - set(self.PREVIEW_JOB_EXCLUSIONS))
        self.assertEqual(
            unpinned, [],
            f"these execute in the preview job (directly or via import) but are not "
            f"pinned in PREVIEW_PRODUCER_PATHS: {unpinned}",
        )

    # ---- runtime-READ data files (the class the closure walk cannot see) ----
    #
    # The closure walk follows what the preview job EXECUTES. A file that is only
    # READ at runtime -- by the Supabase CLI, by `jq`, by `psql` -- never appears
    # in it. `supabase/config.toml` was exactly that file: the CLI reads it on
    # every `link`, `migration list` and `db push` the preview job runs, and it
    # was pinned by neither commit and covered by no test. The two tests below
    # close that class, from both directions.

    @staticmethod
    def uncommented(text):
        """Lines with whole-line `#` / `//` comments dropped.

        Deliberately conservative: only lines whose FIRST non-blank character
        starts a comment are removed. A path named inside a comment is prose, not
        a read; a path named in code is a read until someone proves otherwise.
        """
        out = []
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("#") or stripped.startswith("//"):
                continue
            out.append(line)
        return "\n".join(out)

    def test_preview_producer_paths_cover_runtime_read_data_files(self):
        """Every data file under the preview job's data surface is pinned or explained.

        Driven by the FILESYSTEM, not by a hand-written list, so a data file added
        later cannot slip in silently: it fails this test until someone either
        pins it in PREVIEW_PRODUCER_PATHS or writes down, here, why it cannot
        shape preview evidence. That written reason is the artifact a reader who
        does not trust the author can check.
        """
        repo_root = Path(__file__).resolve().parents[1]
        pinned = set(PREVIEW_PRODUCER_PATHS)

        # The specific file this test exists for. Named explicitly so a future
        # edit that drops it from the tuple fails here with the reason attached,
        # not with a generic diff.
        self.assertIn(
            "supabase/config.toml", pinned,
            "the Supabase CLI reads supabase/config.toml on every preview link, "
            "migration list and db push; unpinned, a pre-merge claim-lane rehearsal "
            "could alter CLI behaviour between rehearsal and promotion",
        )

        # An exemption must describe something that exists, and must not also be
        # pinned -- a path that is both is a contradiction a reader cannot resolve.
        for key, reason in PREVIEW_RUNTIME_DATA_EXEMPTIONS.items():
            self.assertTrue(
                (repo_root / key).exists(),
                f"stale runtime-read exemption: {key} no longer exists. Delete the "
                f"entry rather than leaving a reason nobody can check.",
            )
            self.assertNotIn(
                key, pinned,
                f"{key} is both pinned and exempted; one of the two is wrong",
            )
            # A one-word "n/a" is not a reason. The bar is a sentence a reviewer
            # can disagree with.
            self.assertGreaterEqual(
                len(reason), 120,
                f"runtime-read exemption for {key} is too thin to check: {reason!r}",
            )

        unexplained = []
        for directory in PREVIEW_RUNTIME_DATA_DIRS:
            base = repo_root / directory
            self.assertTrue(base.is_dir(), f"declared data surface missing: {directory}")
            for path in sorted(base.rglob("*")):
                if not path.is_file():
                    continue
                rel = path.relative_to(repo_root).as_posix()
                if rel in pinned or rel in PREVIEW_RUNTIME_DATA_EXEMPTIONS:
                    continue
                # A directory-level exemption covers everything beneath it.
                if any(
                    rel.startswith(f"{key}/") for key in PREVIEW_RUNTIME_DATA_EXEMPTIONS
                ):
                    continue
                unexplained.append(rel)
        self.assertEqual(
            unexplained, [],
            "these files live on the preview job's data surface but are neither "
            "pinned in PREVIEW_PRODUCER_PATHS nor given a written reason in "
            f"PREVIEW_RUNTIME_DATA_EXEMPTIONS: {unexplained}. If a tool in the "
            "preview job can read it, pin it. If it cannot, say why, in words a "
            "reader can check.",
        )

    @staticmethod
    def repository_paths_named_in(text, repo_root):
        """Repository files a body names, in every spelling the workflow uses.

        THREE SPELLINGS, not one. The first version of this scanner matched only
        a bare relative path, so `$GITHUB_WORKSPACE/types/database.types.ts`,
        `./config/x.json` and a slash-less root file all slipped past it -- and a
        mutation proving the scanner "bites" only bites in the one spelling it
        happens to use. The runner-temp prefixes must still NOT match: a copy
        under `$RUNNER_TEMP` is not the checkout.
        """
        found = set()
        # 1. explicit workspace-rooted reads, which is how the heredocs spell it.
        for match in re.findall(
            r"\$(?:GITHUB_WORKSPACE|\{GITHUB_WORKSPACE\})/([A-Za-z0-9_.\-/]+)", text
        ):
            found.add(match.rstrip("."))
        # 2. `./`-prefixed and bare relative paths.
        for match in re.findall(r"(?<![\w./$-])\.?/?((?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+)", text):
            found.add(match.rstrip("."))
        # 3. slash-less repository-ROOT files (`AGENTS.md`, a stray `seed.sql`).
        for match in re.findall(r"(?<![\w./$-])([A-Za-z0-9_-]+\.[A-Za-z0-9]+)(?![\w/])", text):
            found.add(match.rstrip("."))
        return {rel for rel in found if (repo_root / rel).is_file()}

    @staticmethod
    def repository_dirs_named_in(text, repo_root):
        """Top-level repository DIRECTORIES a body names as a whole literal.

        THE GAP THIS CLOSES (#1213 review, round 5, finding 3). The path scanner
        above keeps whole-literal paths only, which is right for a read spelled
        `open("config/foo.json")` and useless against a read the producer BUILDS:
        `Path("policy") / "routing.json"` and `os.path.join("policy",
        "routing.json")` emit `"policy"` and `"routing.json"` as two separate
        literals. Neither trips the path scanner -- `"policy"` has no extension,
        and `"routing.json"` only matches if that name exists at the repository
        root -- so a whole data directory one step outside the declared surface
        was invisible to a test that claimed to cover it.

        A producer that names a top-level directory of this repository at all is
        therefore reported. That is deliberately blunter than "names it AND then
        reads a child": the child half is exactly the half a constructed path can
        hide, so requiring it would put the hole back.
        """
        # EXACT CASE. `(repo_root / name).is_dir()` is case-INSENSITIVE on
        # Windows and macOS, so the bare word `Supabase` in a shell message
        # resolved to the `supabase` directory and reported a read nobody made.
        # The real directory names are listed once and matched exactly instead.
        real = {entry.name for entry in repo_root.iterdir() if entry.is_dir()}
        found = set()
        for match in re.findall(r"(?<![\w./$-])([A-Za-z0-9_-]+)(?![\w/.])", text):
            if match in real:
                found.add(match)
        return found

    @staticmethod
    def scannable_text(path, body):
        """Reduce a body to the parts where a repository READ can actually appear.

        Blunt comment-stripping is not enough, because these scripts explain
        themselves at length: `AGENTS.md`, `HANDOFF.md` and `docs/*.md` appear in
        docstrings AND inside prose sentences in error messages. Deleting every
        string literal instead would delete the real reads too, since a path a
        script opens IS a string literal.

        So a Python body is tokenised and reduced to string literals whose WHOLE
        content is a path -- `"config/atomic-migration-allowlist.json"` survives,
        `"see docs/foo.md section 3"` does not, and a docstring never survives.
        That is the shape a read has and the shape a citation does not.

        A JavaScript body is treated the same way, for the same reason: a read
        there is `path.join(root, 'AGENTS.md')` -- a whole-literal path -- while a
        citation is a sentence that happens to contain one.
        """
        if path.suffix in {".mjs", ".js"}:
            literals = re.findall(r"'([^'\n]*)'|\"([^\"\n]*)\"|`([^`\n]*)`", body)
            return "\n".join(
                value.strip()
                for group in literals for value in group
                if value and re.fullmatch(r"[A-Za-z0-9_.\-/]+", value.strip())
            )
        if path.suffix != ".py":
            text = re.sub(r"/\*.*?\*/", " ", body, flags=re.S)
            return ProductionBusinessRiskGateTests.uncommented(text)
        import ast
        literals = []
        try:
            tree = ast.parse(body)
        except SyntaxError:  # pragma: no cover - a syntax error fails elsewhere
            return ""
        docstrings = set()
        for node in ast.walk(tree):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                first = (node.body or [None])[0]
                if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) \
                        and isinstance(first.value.value, str):
                    docstrings.add(id(first.value))
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) \
                    and id(node) not in docstrings:
                value = node.value.strip()
                if re.fullmatch(r"[A-Za-z0-9_.\-/]+", value):
                    literals.append(value)
        return "\n".join(literals)

    def test_preview_runtime_data_dirs_are_the_only_data_surface(self):
        """PREVIEW_RUNTIME_DATA_DIRS must be exhaustive, not merely declared.

        The two walks below it are each bounded by that tuple: the inward walk
        only descends `supabase/` and `config/`, and the outward walk only sees
        what the JOB TEXT spells out. So a data file at `policy/routing.json`, at
        `types/`, or at the repository root, read at runtime by a PINNED producer
        through a path the producer constructs, escapes both -- one directory
        over from where `supabase/config.toml` was found.

        This closes that gap from the third direction: it reads the executed
        closure's own source, plus the job text, and fails on a reference to any
        repository file outside the declared data surface (the closure's own
        scripts and workflows excepted -- those are pinned by blob, not by
        directory).
        """
        repo_root = Path(__file__).resolve().parents[1]
        closure = self.executed_closure()
        bodies = [self.uncommented(self.preview_job_text())]
        for rel in sorted(closure):
            path = repo_root / rel
            if path.is_file():
                bodies.append(self.scannable_text(path, path.read_text(encoding="utf-8", errors="ignore")))
        # Code directories, not DATA directories: files here are pinned
        # individually in PREVIEW_PRODUCER_PATHS and walked by the closure test,
        # so they are not part of the data-surface question.
        code_dirs = {"scripts", ".github"}
        declared = set(PREVIEW_RUNTIME_DATA_DIRS) | code_dirs
        undeclared = set()
        for body in bodies:
            for rel in self.repository_paths_named_in(body, repo_root):
                top = rel.split("/")[0]
                if "/" not in rel:
                    undeclared.add(rel)          # a repository-ROOT data file
                elif top not in declared:
                    undeclared.add(rel)
            # CONSTRUCTED READS. A producer that assembles its own path never
            # emits the whole path as one literal, so the directory half is the
            # only half a scanner can see. See repository_dirs_named_in.
            for directory in self.repository_dirs_named_in(body, repo_root):
                if directory not in declared \
                        and directory not in PREVIEW_RUNTIME_DATA_EXEMPTIONS:
                    undeclared.add(directory)
        # The scan must be matching something, or this test passes vacuously.
        self.assertTrue(
            any(
                rel.startswith("supabase/") or rel.startswith("config/")
                for body in bodies
                for rel in self.repository_paths_named_in(body, repo_root)
            ),
            "the data-surface scan matched no declared-surface file; the pattern has rotted",
        )
        self.assertEqual(
            sorted(undeclared - set(PREVIEW_PRODUCER_PATHS)), [],
            "the preview job or a script it executes names these repository files, which "
            f"lie OUTSIDE PREVIEW_RUNTIME_DATA_DIRS {PREVIEW_RUNTIME_DATA_DIRS}: "
            f"{sorted(undeclared - set(PREVIEW_PRODUCER_PATHS))}. Either the tuple is no "
            "longer exhaustive -- widen it and re-run the walks -- or the file must be "
            "pinned in PREVIEW_PRODUCER_PATHS.",
        )

    def test_preview_job_reads_no_repository_file_outside_the_pinned_surface(self):
        """The other direction: nothing the workflow names escapes the pin.

        The test above walks the data directories inward. This one walks the
        preview job's own text outward, so a NEW step that reads a repository
        file from some third location -- `types/`, `apps/`, `docs/` -- fails here
        instead of quietly widening the evidence-producing surface. Only paths
        that actually resolve to a file in this repository are considered, which
        drops action references such as `supabase/setup-cli@v1`.
        """
        repo_root = Path(__file__).resolve().parents[1]
        job = self.uncommented(self.preview_job_text())
        # A repo-relative path is one NOT preceded by another path character, so
        # `$RUNNER_TEMP/bounded-preview/supabase/migrations` -- a runner-temp copy,
        # not the checkout -- is correctly not treated as a repository read.
        referenced = self.repository_paths_named_in(job, repo_root)
        # THE EXEMPTION IS ABOUT THE PREVIEW JOB, WHICH IS NOT THE JOB YAML.
        # Asserting the "never read" premise against the workflow text alone let
        # a PINNED SCRIPT start reading `supabase/tests/foo.sql` while both this
        # test and the inward walk stayed green -- the inward walk treats
        # everything under an exempted directory as exempt, and the job text
        # never mentions the script's own reads (#1213 review, round 5, finding
        # 3). The closure's scannable text is added, so a read that moves into a
        # script is still a read by the preview job.
        executed = set(referenced)
        for rel in sorted(self.executed_closure()):
            path = repo_root / rel
            if path.is_file():
                executed |= self.repository_paths_named_in(
                    self.scannable_text(
                        path, path.read_text(encoding="utf-8", errors="ignore")
                    ),
                    repo_root,
                )
        # Guard against the scan silently matching nothing, which would make this
        # test pass through an unasserted condition -- a defect in itself.
        self.assertIn(
            "scripts/production_migration_guard.py", referenced,
            "the preview-job path scan matched nothing recognisable; the pattern "
            "has rotted and this test is no longer checking anything",
        )
        # ONLY the payload is whitelisted. Whitelisting the other three
        # exemptions would let a future step that DOES read one of them leave
        # this test green while falsifying the written reason -- exactly the
        # failure the registry exists to catch. Their premise is asserted
        # instead, immediately below, the way PREVIEW_JOB_EXCLUSIONS already is.
        allowed = set(PREVIEW_PRODUCER_PATHS) | set(self.PREVIEW_JOB_EXCLUSIONS) | {PREVIEW_WORKFLOW}
        allowed.add("supabase/migrations")
        for key, reason in PREVIEW_RUNTIME_DATA_EXEMPTIONS.items():
            if "Never read by the preview job" not in reason:
                continue
            self.assertNotIn(
                key, executed,
                f"{key} is exempted because it is 'Never read by the preview job', "
                f"but the preview job or a script it executes now names it. Pin it in "
                f"PREVIEW_PRODUCER_PATHS or rewrite the reason -- do not leave a reason "
                f"the code contradicts.",
            )
            for rel in sorted(executed):
                self.assertFalse(
                    rel.startswith(f"{key}/"),
                    f"{key} is exempted as never read by the preview job, but the job "
                    f"or a script it executes now names {rel} beneath it",
                )
        escaped = sorted(
            rel for rel in referenced
            if rel not in allowed and not rel.startswith("supabase/migrations/")
        )
        self.assertEqual(
            escaped, [],
            "the preview job names these repository files, but they are neither "
            f"pinned nor explained: {escaped}. Anything the preview job reads can "
            "shape its evidence.",
        )

    def test_every_pinned_producer_path_exists(self):
        """A typo in the tuple would silently pin nothing but fail closed later."""
        repo_root = Path(__file__).resolve().parents[1]
        for path in PREVIEW_PRODUCER_PATHS:
            self.assertTrue((repo_root / path).is_file(), f"pinned producer path missing: {path}")

    def test_preview_ledger_delta_rejects_extra_additions_removals_and_prior_version(self):
        cases = [
            ({"old"}, {"old", "20260816110750", "extra"}),
            ({"old"}, {"20260816110750"}),
            ({"20260816110750"}, {"20260816110750"}),
        ]
        for before, after in cases:
            temp, root, version, _, texts = self.atomic_preview_fixture()
            with self.subTest(before=before, after=after), temp, self.assertRaisesRegex(RiskGateError, "delta"):
                prove_preview_migration_contents(
                    texts=texts, allowlist=[version], repo_root=root,
                    before_versions=before, after_versions=after, historical=False,
                )
    def test_inactive_policy_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp, "activation.json")
            path.write_text('{"active":false,"schema_version":"shared-db-production-risk-activation/v1"}\n')
            data = load_activation(path)
            with self.assertRaisesRegex(RiskGateError, "old exact owner-approval rule"):
                prove_activation(data, main_sha="a" * 40, api=lambda _: {}, repo_root=Path(temp))

    def test_forged_activation_booleans_and_prose_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp, "activation.json")
            path.write_text(json.dumps({"active": True, "evidence": "trust me"}))
            with self.assertRaisesRegex(RiskGateError, "forged or incomplete"):
                load_activation(path)

    def test_installed_skill_hash_must_equal_canonical(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp, "activation.json")
            data = {
                "active": True, "schema_version": "shared-db-production-risk-activation/v2",
                "shared_db_pr": 1021, "shared_db_merge_sha": "a" * 40,
                "ai_devops_pr": 24, "ai_devops_merge_sha": "b" * 40,
                "skill_hashes": {
                    "SKILL.md": {"canonical": "c" * 64, "codex_installed": "d" * 64, "claude_installed": "c" * 64},
                    "references/operating-manual.md": {"canonical": "e" * 64, "codex_installed": "e" * 64, "claude_installed": "e" * 64},
                    "agents/openai.yaml": {"canonical": "f" * 64, "codex_installed": "f" * 64, "claude_installed": "f" * 64},
                },
                "forward_test_path": "docs/verification/issue-1039-production-risk-activation-forward-proof.md",
                "forward_test_sha256": "a" * 64,
            }
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(RiskGateError, "does not match"):
                load_activation(path)

    def test_static_analysis_is_conservative(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            migrations = root / "supabase/migrations"
            migrations.mkdir(parents=True)
            (migrations / "20260814000000_safe.sql").write_text("create table core.safe(id bigint); insert into core.safe values (1);")
            self.assertEqual(classify_sql(root, ["20260814000000"]), [])
            (migrations / "20260814000001_risky.sql").write_text("alter table core.safe add column x text; revoke select on core.safe from anon;")
            reasons = classify_sql(root, ["20260814000001"])
            self.assertIn("users may be interrupted", reasons)
            self.assertIn("access or permissions materially change", reasons)

    def test_synthetic_low_risk_and_all_five_risk_classes_fail_closed(self):
        self.assertEqual(
            decide_business_risk([], recovery_proven=True, review_approved=True),
            {"automaticPromotionAllowed": True, "ownerDecisionReasons": []},
        )
        cases = [
            (["existing production data may be lost or permanently altered"], True, True),
            (["users may be interrupted"], True, True),
            (["access or permissions materially change"], True, True),
            ([], False, True),
            ([], True, False),
        ]
        for sql_reasons, recovery, review in cases:
            with self.subTest(sql_reasons=sql_reasons, recovery=recovery, review=review):
                result = decide_business_risk(sql_reasons, recovery_proven=recovery, review_approved=review)
                self.assertFalse(result["automaticPromotionAllowed"])
                self.assertEqual(len(result["ownerDecisionReasons"]), 1)

    def test_forged_preview_claim_is_rejected_before_download(self):
        forged = "b" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": forged, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        api = self.preview_api(
            run, [{"sha": "a" * 40}], {}, [self.apply_artifact(forged)],
            compare={"status": "diverged", "ahead_by": 1, "behind_by": 1},
        )
        with self.assertRaisesRegex(RiskGateError, "not contained in the history of exact main"):
            prove_preview(
                **self.prove_preview_args(api=api),
                downloader=lambda *_: self.fail("forged run must not download"),
            )

    def test_preview_artifact_must_match_pinned_run_and_digest_before_download(self):
        head = "a" * 40
        run = {
            "status": "completed", "conclusion": "success", "event": "workflow_dispatch",
            "head_sha": head, "path": ".github/workflows/shared-supabase-migrations.yml",
        }
        artifact = {
            "id": 9,
            "name": f"preview-migration-apply-{head}",
            "digest": "sha256:" + "d" * 64,
            "expired": False,
            "workflow_run": {"id": 7},
        }

        def api(endpoint):
            if endpoint.endswith("artifacts?per_page=100"):
                return {"artifacts": [artifact]}
            if endpoint.endswith("commits?per_page=100"):
                return [{"sha": head}]
            if "/git/trees/" in endpoint:
                return {"truncated": False,
                        "tree": [{"path": p} for p in PREVIEW_PRODUCER_PATHS]}
            if "/contents/" in endpoint:
                # Producer files identical at the run head and at main, so this
                # test still exercises the digest check it is named for.
                return {"sha": "identical-producer-blob"}
            return run

        with self.assertRaisesRegex(RiskGateError, "pinned digest"):
            prove_preview(
                **self.prove_preview_args(pr_head=head, main_sha="b" * 40, api=api),
                downloader=lambda *_: self.fail("wrong digest must not download"),
            )

        artifact["digest"] = "sha256:" + "c" * 64
        artifact["workflow_run"] = {"id": 8}
        with self.assertRaisesRegex(RiskGateError, "another run"):
            prove_preview(
                **self.prove_preview_args(pr_head=head, main_sha="b" * 40, api=api),
                downloader=lambda *_: self.fail("wrong run must not download"),
            )

    def test_production_workflow_enforces_gate_twice_and_keeps_old_boundary(self):
        workflow = Path(__file__).parents[1] / ".github/workflows/shared-supabase-migrations.yml"
        text = workflow.read_text(encoding="utf-8")
        self.assertEqual(text.count("python scripts/production_business_risk_gate.py"), 2)
        self.assertIn("environment: production", text)
        self.assertGreaterEqual(text.count("config/production-risk-policy-activation.json"), 2)

    def test_historical_preview_recovery_proves_existing_ledger_without_writing(self):
        workflow = Path(__file__).parents[1] / ".github/workflows/shared-supabase-migrations.yml"
        text = workflow.read_text(encoding="utf-8")
        self.assertIn("Recover proof for migrations already present on preview", text)
        self.assertIn("HISTORICAL PREVIEW PROOF: already applied; no database write performed", text)
        self.assertIn("REFUSED: historical preview recovery is missing ledger versions", text)
        # The ordinary apply path must stay excluded on BOTH historical forms.
        # A batch authored across several PRs supplies a per-version source map
        # and no single source PR, so a condition testing only the single-PR
        # input would let the real apply run during a no-write recovery.
        self.assertIn(
            "inputs.mode == 'apply' && (inputs.historical_preview_source_pr == '' "
            "&& inputs.historical_preview_source_pr_map == '')", text)
        for guarded in ("historical_preview_source_pr == ''", "historical_preview_source_pr_map == ''"):
            self.assertIn(guarded, text)

    def historical_v2_api(self, main, versions, authored=None):
        authored = authored or {pr: v for v, pr in versions.items()}
        def api(endpoint):
            if endpoint.endswith("commits?per_page=100"):
                return [{"sha": main}]
            if "/contents/" in endpoint:
                return {"sha": "identical-producer-blob"}
            if "/pulls/" in endpoint and "/files" in endpoint:
                pr = int(endpoint.split("/pulls/")[1].split("/")[0])
                version = authored.get(pr)
                return [] if version is None else [
                    {"filename": f"supabase/migrations/{version}_release_a.sql", "status": "added"}]
            if "/pulls/" in endpoint:
                return {"merged": True, "merge_commit_sha": main}
            return {}
        return api

    def test_gate_rejects_a_v2_record_whose_map_names_the_wrong_pull_request(self):
        """A forged map must not pass just because it lives in a pinned artifact.

        The map is attacker-influenced: it arrives inside the preview artifact.
        The gate re-derives from it, so the protection is that re-derivation
        FAILS for a mapping that does not match real authorship.
        """
        from historical_preview_recovery import verify as verify_historical
        versions = {"20260814130000": 984, "20260814193402": 992}
        main = "e" * 40
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "supabase/migrations").mkdir(parents=True)
            for version in versions:
                (root / f"supabase/migrations/{version}_release_a.sql").write_text("select 1;", encoding="utf-8")
            subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.DEVNULL)
            subprocess.run(["git", "config", "user.email", "x@y"], cwd=root)
            subprocess.run(["git", "config", "user.name", "x"], cwd=root)
            subprocess.run(["git", "add", "."], cwd=root)
            subprocess.run(["git", "commit", "-m", "x"], cwd=root, check=True, stdout=subprocess.DEVNULL)
            real = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
            api = self.historical_v2_api(real, versions)
            # Honest map re-derives cleanly.
            runs = "20260814130000:9001,20260814193402:9002"
            honest = verify_historical(None, real, ",".join(sorted(versions)), root, api,
                                       source_map="20260814130000:984,20260814193402:992",
                                       original_run_map=runs)
            self.assertEqual(honest["schema"], "shared-db-historical-preview-source/v4")
            # Swapping the PRs is refused, so a forged record cannot re-derive.
            with self.assertRaisesRegex(ValueError, "did not author"):
                verify_historical(None, real, ",".join(sorted(versions)), root, api,
                                  source_map="20260814130000:992,20260814193402:984",
                                  original_run_map=runs)

    # ---- the historical-recovery byte binding (review round 4, finding 1) ----
    #
    # A recovery run writes nothing, so for a long time this lane waived byte
    # equality entirely: it proved authorship and ledger presence, and the
    # sequence "rehearse harmless bytes A, amend the file to destructive bytes B,
    # merge, recover proof, promote B" walked straight through the last gate
    # before a production write. The record must now name the run that ORIGINALLY
    # applied each version, and the gate reads that run's own manifest.

    HISTORICAL_VERSION = "20260814130000"

    def historical_repo(self, body="select 1;\n"):
        """A real git repo, because the recovery proof shells out to git.

        TWO commits, and the distinction matters: the FIRST is the merge commit
        that landed the migration, the SECOND is today's exact main. They were
        the same commit until the #1213 round-6 review, which left every
        "pinned to the merge commit" test unable to tell that pin apart from
        "pinned to today's main".
        """
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        (root / "supabase/migrations").mkdir(parents=True)
        (root / f"supabase/migrations/{self.HISTORICAL_VERSION}_release_a.sql").write_bytes(
            body.encode("utf-8")
        )
        subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "config", "user.email", "x@y"], cwd=root)
        subprocess.run(["git", "config", "user.name", "x"], cwd=root)
        subprocess.run(["git", "add", "."], cwd=root)
        subprocess.run(["git", "commit", "-m", "x"], cwd=root, check=True, stdout=subprocess.DEVNULL)
        merge_sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        (root / "later.txt").write_text("main moved on\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=root)
        subprocess.run(["git", "commit", "-m", "later"], cwd=root, check=True,
                       stdout=subprocess.DEVNULL)
        main = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        return temp, root, main, merge_sha

    def historical_zip(self, path, *, main, record, version):
        """The RECOVERY run's evidence: no write, so the ledger must not move."""
        ledger = json.dumps([{"remote": "20260801000000"}, {"remote": version}])
        payload = {
            "preview-ledger-before.txt": ledger,
            "preview-ledger-after.txt": ledger,
            "preview-dry-run.txt": f"HISTORICAL PREVIEW PROOF\n{version}_release_a.sql\n",
            "preview-apply.txt": f"HISTORICAL PREVIEW PROOF\n{version}_release_a.sql\n",
            "historical-preview-source.json": json.dumps(record),
            "preview-instance.json": json.dumps({
                "schema": "shared-db-preview-instance-binding/v1",
                "rehearsalMode": "historical-recovery", "appliedCommit": main,
                "previewProjectRef": PREVIEW_PROJECT_REF, "runId": 7,
                "allowlist": [version],
            }),
        }
        with zipfile.ZipFile(path, "w") as archive:
            for name, text in payload.items():
                archive.writestr(name, text)
        return "sha256:" + hashlib.sha256(Path(path).read_bytes()).hexdigest()

    def original_run_zip(self, path, *, version, digest, applied=True, recovery=False,
                         instance=None):
        """The ORIGINAL apply run's evidence: it really moved preview's ledger."""
        before = json.dumps([{"remote": "20260801000000"}])
        after = json.dumps(
            [{"remote": "20260801000000"}] + ([{"remote": version}] if applied else [])
        )
        payload = {
            "preview-ledger-before.txt": before,
            "preview-ledger-after.txt": after,
            "preview-dry-run.txt": f"Applying migration {version}_release_a.sql...",
            "preview-apply.txt": f"Applying migration {version}_release_a.sql...",
            "migration-content-manifest.json": json.dumps({version: digest}),
        }
        if recovery:
            payload["historical-preview-source.json"] = json.dumps({"schema": "x"})
        if instance is not None:
            payload["preview-instance.json"] = instance
        with zipfile.ZipFile(path, "w") as archive:
            for name, text in payload.items():
                archive.writestr(name, text)

    def run_historical_prove_preview(
        self, *, rehearsed_body="select 1;\n", main_body="select 1;\n",
        original_run=555, record_runs="default", original_applied=True,
        original_is_recovery=False, original_conclusion="success",
        original_head_sha="default", original_head_in_history=True,
        original_head_blobs=None, original_run_blobs=None, original_instance=None,
        merge_commit_blobs=None, merge_absent_paths=(), original_absent_paths=(),
    ):
        """End to end through prove_preview, downloads and all.

        `rehearsed_body` is what the ORIGINAL run recorded a digest for;
        `main_body` is what exact main carries now. Equal in the honest case,
        different in the attack.

        THE ORIGINAL RUN HAS TWO COMMITS, and the last four arguments exist so a
        test can drive them apart, which the first version of this helper could
        not: it always set `head_sha` equal to the artifact-name commit and always
        listed that commit as a commit of the source PR, so no forged dispatch was
        reachable through this path at all (#1213 review, round 5, finding 1).

        * `original_head_sha` -- the ref the ORIGINAL dispatch was aimed at.
        * `original_head_in_history` -- whether exact main contains it.
        * `original_head_blobs` -- producer blobs at the DISPATCH REF only, so a
          doctored workflow at an otherwise honest-looking ref can be expressed.
        * `original_run_blobs` -- producer blobs at BOTH of the original run's
          commits, i.e. an old run that is internally consistent but carries
          producer files today's main no longer has. A pin aimed at today's main
          fails on this; a pin aimed at the authoring merge commit passes it only
          when `merge_commit_blobs` carries the same values.
        * `merge_commit_blobs` -- producer blobs at the MERGE COMMIT that landed
          the version, separated from every other ref so a test can state which
          commit the pin is really aimed at. The round-5 helper could not: it
          defaulted every blob to one value and used one commit for the merge
          commit and for main, so "pinned to each other" and "pinned to the merge
          commit" were indistinguishable (#1213 round 6, finding 1).
        * `original_instance` -- the raw `preview-instance.json` that run wrote,
          or None for a run whose producer code predates instance binding.
        * `merge_absent_paths` / `original_absent_paths` -- producer files that
          do NOT exist at the merge commit / at the original run's commits.
          `scripts/preview_instance_binding.py` really is absent at the merge
          commits of #984, #992 and #1126, and #984/#992 additionally predate
          `scripts/atomic_migration_apply.py`,
          `scripts/historical_preview_recovery.py` and
          `config/atomic-migration-allowlist.json` (verified with `gh api`).
        """
        version = self.HISTORICAL_VERSION
        temp, root, main, merge_sha = self.historical_repo(main_body)
        with temp:
            rehearsed_digest = hashlib.sha256(rehearsed_body.encode("utf-8")).hexdigest()
            record = {
                "schema": "shared-db-historical-preview-source/v3",
                "sourcePr": 984, "sourceMergeSha": merge_sha, "mainSha": main,
                "allowlist": [version],
                "originalApplyRuns": {version: original_run}
                if record_runs == "default" else record_runs,
            }
            zips = tempfile.TemporaryDirectory()
            with zips:
                recovery_path = Path(zips.name, "recovery.zip")
                artifact_digest = self.historical_zip(
                    recovery_path, main=main, record=record, version=version
                )
                original_path = Path(zips.name, "original.zip")
                self.original_run_zip(
                    original_path, version=version, digest=rehearsed_digest,
                    applied=original_applied, recovery=original_is_recovery,
                    instance=original_instance,
                )
                original_commit = "a" * 40
                original_head = (
                    original_commit if original_head_sha == "default" else original_head_sha
                )
                pr_commits = [{"sha": main}, {"sha": original_commit}]

                def producer_tree(ref):
                    """Which producer files that commit's tree actually holds.

                    `PREVIEW_PRODUCER_PATHS` is TODAY's list. A commit from last
                    year does not carry a file added this year, and the two
                    `*_absent_paths` arguments are how a test says so.
                    """
                    if ref == merge_sha:
                        absent = set(merge_absent_paths)
                    elif ref in (original_head, original_commit):
                        absent = set(original_absent_paths)
                    else:
                        absent = set()
                    return [p for p in PREVIEW_PRODUCER_PATHS if p not in absent]

                def api(endpoint):
                    if endpoint == f"repos/u2giants/shared-db/actions/runs/{original_run}":
                        run = {"status": "completed", "conclusion": original_conclusion,
                               "event": "workflow_dispatch", "path": PREVIEW_WORKFLOW}
                        if original_head is not None:
                            run["head_sha"] = original_head
                        return run
                    if endpoint.endswith(f"runs/{original_run}/artifacts?per_page=100"):
                        return {"artifacts": [self.apply_artifact(
                            original_commit, artifact_id=99, run_id=original_run)]}
                    if endpoint == "repos/u2giants/shared-db/actions/runs/7":
                        return {"status": "completed", "conclusion": "success",
                                "event": "workflow_dispatch", "head_sha": main,
                                "path": PREVIEW_WORKFLOW}
                    if endpoint.endswith("runs/7/artifacts?per_page=100"):
                        return {"artifacts": [self.apply_artifact(main, digest=artifact_digest)]}
                    if endpoint.endswith("commits?per_page=100"):
                        return pr_commits
                    if "/git/trees/" in endpoint:
                        ref = endpoint.split("/git/trees/", 1)[1].split("?")[0]
                        return {"truncated": False,
                                "tree": [{"path": p} for p in producer_tree(ref)]}
                    if "/contents/" in endpoint:
                        path, ref = endpoint.split("/contents/", 1)[1].split("?ref=")
                        # RAISE ON A PATH THAT IS NOT IN THAT TREE, exactly as
                        # GitHub 404s and exactly as `preview_api` already did.
                        # The round-6 version of this stub answered
                        # "identical-producer-blob" for EVERY path including
                        # files that did not exist, which is why three mutation
                        # runs could not see that the recovery lane refused
                        # every honest old recovery (#1213 round 7, finding 1).
                        if path not in producer_tree(ref):
                            raise RuntimeError("no such content")
                        if merge_commit_blobs and ref == merge_sha:
                            return {"sha": merge_commit_blobs.get(
                                path, "identical-producer-blob")}
                        if original_head_blobs and ref == original_head:
                            return {"sha": original_head_blobs.get(
                                path, "identical-producer-blob")}
                        if original_run_blobs and ref in (original_head, original_commit):
                            return {"sha": original_run_blobs.get(
                                path, "identical-producer-blob")}
                        return {"sha": "identical-producer-blob"}
                    if "/pulls/" in endpoint and "/files" in endpoint:
                        return [{"filename":
                                 f"supabase/migrations/{version}_release_a.sql",
                                 "status": "added"}]
                    if "/pulls/" in endpoint:
                        return {"merged": True, "merge_commit_sha": merge_sha}
                    if "/compare/" in endpoint:
                        base = endpoint.split("/compare/", 1)[1].split("...")[0]
                        if base == original_head and not original_head_in_history:
                            return {"status": "diverged", "behind_by": 3}
                        return {"status": "identical", "behind_by": 0}
                    return {}

                def downloader(artifact_id, dest):
                    source = original_path if artifact_id == 99 else recovery_path
                    Path(dest).write_bytes(source.read_bytes())

                prove_preview(
                    run_id=7, digest=artifact_digest, pr_head=main, main_sha=main,
                    source_pr=984, allowlist=[version],
                    preview_project_ref=PREVIEW_PROJECT_REF, merge_commit_sha=main,
                    api=api, repo_root=root, downloader=downloader,
                )

    def test_historical_recovery_is_accepted_when_preview_ran_the_promoted_bytes(self):
        """The honest case still promotes: same bytes rehearsed and merged."""
        self.run_historical_prove_preview()

    def test_historical_recovery_of_amended_bytes_is_refused(self):
        """THE ATTACK. Rehearse A on preview, amend the file to B, merge, recover.

        Every other historical check passes: the file is on exact main, the proof
        names it, both ledgers hold it, the source PR added it, the applied commit
        IS exact main. Only the byte comparison against the ORIGINAL apply run
        catches it -- and production would otherwise have applied bytes preview
        never executed.
        """
        with self.assertRaisesRegex(RiskGateError, "different bytes than exact main"):
            self.run_historical_prove_preview(
                rehearsed_body="select 1;\n", main_body="drop table core.customer;\n"
            )

    def test_historical_recovery_without_an_original_run_map_is_refused(self):
        """The pre-#1213 record shape, and any record that simply omits it."""
        for runs in ({}, None, "not-a-map"):
            with self.subTest(runs=runs), self.assertRaisesRegex(
                RiskGateError, "does not name the original apply run"
            ):
                self.run_historical_prove_preview(record_runs=runs)

    def test_original_run_that_did_not_move_the_ledger_is_refused(self):
        """Naming a run that merely MENTIONED the version proves nothing."""
        with self.assertRaisesRegex(RiskGateError, "did not apply"):
            self.run_historical_prove_preview(original_applied=False)

    def test_a_recovery_may_not_cite_another_recovery(self):
        """Otherwise recoveries could cite recoveries forever, touching no byte."""
        with self.assertRaisesRegex(RiskGateError, "itself a historical recovery"):
            self.run_historical_prove_preview(original_is_recovery=True)

    def test_original_run_must_have_succeeded(self):
        with self.assertRaisesRegex(RiskGateError, "has wrong conclusion"):
            self.run_historical_prove_preview(original_conclusion="failure")

    def test_forged_dispatch_ref_cannot_fabricate_a_historical_original_run(self):
        """#1213 review, round 5, finding 1. The exact twin of
        `test_forged_dispatch_ref_cannot_fabricate_a_main_line_rehearsal`, on the
        recovery lane -- the lane that supplies the BYTES.

        THE FORGE. Preview honestly holds the version from an apply of bytes A.
        The file on main was later amended to bytes B. An attacker pushes branch
        `evil` whose copy of the workflow performs no database write and instead
        hand-writes `preview-ledger-before.txt` without the version,
        `preview-ledger-after.txt` with it, and a `migration-content-manifest.json`
        mapping the version to the sha256 of B on exact main, with no
        `historical-preview-source.json`. They dispatch it at `--ref evil`, name
        the upload `preview-migration-apply-<any commit of the authoring PR>`,
        then recover and promote.

        Every other check in `prove_historical_original_apply_runs` passes: the
        run is a successful dispatch of this workflow, it carries exactly one
        unexpired apply artifact, it is not itself a recovery, its ledger gains
        the version, and the digest it recorded equals exact main. Production
        would apply B; preview ran A.

        Only `head_sha` -- the ref GitHub read the workflow FILE from, which no
        part of the artifact can restate -- exposes it.
        """
        with self.assertRaisesRegex(RiskGateError, "not contained in the history of exact main"):
            self.run_historical_prove_preview(
                original_head_sha="e" * 40, original_head_in_history=False
            )

    def test_original_run_whose_workflow_differs_from_the_merge_commit_is_refused(self):
        """The subtler half of the same forge: a dispatch ref that IS in main's
        history, carrying a doctored workflow.

        Main-line containment alone would accept this -- an ancestor of main is
        ancestor code, and nothing about ancestry says the workflow that ran is
        the workflow that landed. The producer pin does, by comparing the
        dispatch ref against the merge commit of the pull request that authored
        the version. Round 5 compared it against the run's own checkout instead,
        which the attacker also chooses (#1213 round 6, finding 1).
        """
        with self.assertRaisesRegex(RiskGateError, "different .* than the merge commit"):
            self.run_historical_prove_preview(
                original_head_sha="b" * 40,
                original_head_blobs={PREVIEW_WORKFLOW: "doctored-workflow"},
            )

    def test_original_run_without_a_readable_head_sha_is_refused(self):
        """An unreadable dispatch ref is a missing pin, never a passed one."""
        for head in (None, "", "abc", "z" * 40, 12345):
            with self.subTest(head=head), self.assertRaisesRegex(
                RiskGateError, "does not name the commit whose workflow executed"
            ):
                self.run_historical_prove_preview(original_head_sha=head)

    def test_an_honest_old_original_run_still_recovers(self):
        """THE REASON THE PIN IS AIMED AT THE AUTHORING MERGE COMMIT, not today's main.

        This original run was dispatched at one commit of the authoring pull
        request and checked out another, and BOTH carry the producer files that
        the merge commit carries -- which are NOT the ones today's main carries.
        Pinning it to today's main would refuse it, and with it every Sample
        Tracking recovery this lane exists for, so this test fails if anyone
        tightens it that way.

        As written before the #1213 round-6 review this test proved the opposite
        of its name: the helper used one commit for the merge commit and for
        main, and defaulted every blob to one value, so it was itself the shape
        of the forge -- one pull-request commit on both pins, nothing compared.
        """
        old = "the-workflow-as-it-was-then"
        self.run_historical_prove_preview(
            original_head_sha="b" * 40,
            original_run_blobs={PREVIEW_WORKFLOW: old},
            merge_commit_blobs={PREVIEW_WORKFLOW: old},
        )

    def test_original_run_at_a_pr_commit_that_differs_from_the_merge_commit_is_refused(self):
        """#1213 review, round 6, finding 1. THE FORGE ROUND 5 LEFT OPEN.

        Round 5 pinned the original run's two commits TO EACH OTHER, so one
        attacker-chosen commit used for both compared nothing at all. This
        repository squash-merges, so every commit ever pushed to a pull request
        stays in `GET /pulls/{n}/commits` forever -- after the branch is deleted,
        and available to be dispatched again after the merge by recreating a
        branch at it.

        THE FORGE. Honestly apply bytes A through the ordinary claim lane so
        preview's ledger holds the version. Amend the file to destructive bytes
        B. Push commit `D` whose copy of the workflow skips the database write
        and hand-writes both ledgers and a content manifest naming the sha256 of
        B. Dispatch at `D`, so `head_sha` is `D`, and name the upload
        `preview-migration-apply-<D>`. Restore the honest workflow in a later
        commit, merge, then recover naming that run.

        Both pins are `D`. Every other check passes. Production applies B while
        preview ran A. Only a pin to a commit the promoter cannot choose -- the
        MERGE COMMIT, already proved merged and an ancestor of exact main --
        exposes it, and that is what this test holds in place.
        """
        with self.assertRaisesRegex(RiskGateError, "different .* than the merge commit"):
            self.run_historical_prove_preview(
                original_run_blobs={PREVIEW_WORKFLOW: "doctored-workflow-at-one-pr-commit"},
            )

    def test_one_commit_used_for_both_original_pins_is_not_self_evidence(self):
        """The same forge stated as the no-op it exploited.

        `original_head_sha` defaults to the artifact-name commit, so this run has
        ONE commit on both pins -- the exact shape round 5 accepted. It is
        refused now because neither pin is compared against the other any more.
        """
        with self.assertRaisesRegex(RiskGateError, "different .* than the merge commit"):
            self.run_historical_prove_preview(
                original_run_blobs={"scripts/atomic_migration_apply.py": "doctored-apply"},
            )

    def test_a_recovery_record_without_a_usable_merge_commit_is_refused(self):
        """No merge commit, no pin. It must fail closed, never skip the pin."""
        temp, root, main, merge_sha = self.historical_repo()
        with temp:
            for bad in (None, "", "not-a-sha", 12345):
                with self.subTest(bad=bad), self.assertRaisesRegex(
                    RiskGateError, "no usable source merge commit"
                ):
                    record = {"sourcePr": 984, "sourceMergeSha": bad,
                              "originalApplyRuns": {self.HISTORICAL_VERSION: 555}}
                    prove_historical_original_apply_runs(
                        record=record, allowlist=[self.HISTORICAL_VERSION], repo_root=root,
                        main_sha=main, api=lambda endpoint: self.fail(
                            "an unusable merge commit must be refused before any API call"
                        ), downloader=lambda *_: None,
                    )

    def test_producer_comparison_validates_its_target_instead_of_trusting_a_flag(self):
        """The honour-system boolean, replaced by something the function checks.

        Round 7 of the #1213 review: `target_is_proved=True` asserted that the
        second argument was exact main or a proved merge commit, and checked
        neither, so a later caller could pass two equal attacker-chosen commits
        and skip every blob read. The target is TAGGED now and this function
        re-derives the tag:

        * `exact-main` must literally be the main SHA being promoted.
        * `authored-merge` must be contained in the history of that main SHA.

        Identity is accepted only AFTER that validation, so the commit standing
        in for the comparison is one the gate proved, not one the promoter
        picked.
        """
        sha, main = "a" * 40, "3" * 40
        never = lambda endpoint: self.fail("no read for a target that never validates")

        # An untagged / unknown tag is refused outright.
        with self.assertRaisesRegex(RiskGateError, "untagged target"):
            prove_preview_producer_matches_main(
                sha, ProvedTarget("promoter-says-so", sha), main, never,
                what="original apply run 555 dispatched at " + sha,
            )
        # A malformed target commit is refused before any read.
        for bad in (None, "", "not-a-sha", 12345, "A" * 40):
            with self.subTest(bad=bad), self.assertRaisesRegex(RiskGateError, "malformed target"):
                prove_preview_producer_matches_main(
                    sha, ProvedTarget("exact-main", bad), main, never,
                    what="original apply run 555 dispatched at " + sha,
                )
        # THE FORGE THE BOOLEAN ALLOWED: two equal attacker-chosen commits.
        # Tagged exact-main, it is not the main being promoted.
        with self.assertRaisesRegex(RiskGateError, "is not the exact main"):
            prove_preview_producer_matches_main(
                sha, exact_main(sha), main, never,
                what="original apply run 555 dispatched at " + sha,
            )
        # Tagged authored-merge, it is not in main's history.
        with self.assertRaisesRegex(RiskGateError, "not contained in the history of exact main"):
            prove_preview_producer_matches_main(
                sha, authored_merge(sha), main,
                lambda endpoint: {"status": "diverged", "behind_by": 4},
                what="original apply run 555 dispatched at " + sha,
            )
        # And the ancestry read is the ordered compare, not a swapped one.
        seen = []

        def ancestry(endpoint):
            seen.append(endpoint)
            return {"status": "ahead", "behind_by": 0}

        prove_preview_producer_matches_main(
            sha, authored_merge(sha), main, ancestry,
            what="original apply run 555 dispatched at " + sha,
        )
        self.assertEqual(seen, [f"repos/u2giants/shared-db/compare/{sha}...{main}"])
        # A validated exact-main target still short-circuits on identity.
        prove_preview_producer_matches_main(
            main, exact_main(main), main,
            lambda endpoint: self.fail("no blob is read for an identity compare"),
            what="preview run dispatched at " + main,
        )

    def test_a_producer_added_after_the_merge_commit_still_recovers(self):
        """THE HIGH FROM ROUND 7, stated as the recovery it killed.

        `scripts/preview_instance_binding.py` was added by this pull request and
        does not exist at the merge commits of #984, #992 or #1126 -- confirmed
        with real `gh api` reads. #984 and #992 additionally predate
        `scripts/atomic_migration_apply.py`,
        `scripts/historical_preview_recovery.py` and
        `config/atomic-migration-allowlist.json`. Walking TODAY's producer list
        at those commits 404s on the first of them and refuses the recovery
        before a single digest is read -- 100% of the recoveries this lane
        exists for. A path absent from BOTH trees is skipped now: neither run
        could have executed a file that does not exist.
        """
        absent = (
            "scripts/preview_instance_binding.py",
            "scripts/atomic_migration_apply.py",
            "scripts/historical_preview_recovery.py",
            "config/atomic-migration-allowlist.json",
        )
        self.run_historical_prove_preview(
            merge_absent_paths=absent, original_absent_paths=absent,
        )

    def test_a_producer_present_at_the_merge_and_absent_at_the_original_run_is_refused(self):
        """Skipping two absences is safe. Skipping ONE is not.

        A run that did not carry the apply script the merge commit carries did
        not execute the machinery that landed. Both directions refuse.
        """
        path = "scripts/atomic_migration_apply.py"
        with self.assertRaisesRegex(RiskGateError, f"{path} absent where .* has it present"):
            self.run_historical_prove_preview(original_absent_paths=(path,))
        with self.assertRaisesRegex(RiskGateError, f"{path} present where .* has it absent"):
            self.run_historical_prove_preview(merge_absent_paths=(path,))

    def test_a_doctored_producer_that_exists_at_both_commits_is_still_compared(self):
        """The skip must not become a hiding place.

        Absent on both sides is skipped; present on both sides is compared byte
        for byte, even when other producers are being skipped around it.
        """
        with self.assertRaisesRegex(RiskGateError, "different .* than the merge commit"):
            self.run_historical_prove_preview(
                merge_absent_paths=("scripts/preview_instance_binding.py",),
                original_absent_paths=("scripts/preview_instance_binding.py",),
                original_run_blobs={PREVIEW_WORKFLOW: "doctored-workflow"},
            )

    def test_original_run_bound_to_the_production_project_is_refused(self):
        """Evidence of a PRODUCTION write is never a preview rehearsal, at any age."""
        with self.assertRaisesRegex(RiskGateError, "performed against the PRODUCTION project"):
            self.run_historical_prove_preview(
                original_instance=json.dumps({
                    "schema": "shared-db-preview-instance-binding/v1",
                    "previewProjectRef": "qsllyeztdwjgirsysgai",
                })
            )

    def test_original_run_with_an_unreadable_instance_binding_is_refused(self):
        with self.assertRaisesRegex(RiskGateError, "unreadable preview instance binding"):
            self.run_historical_prove_preview(original_instance="{not json")

    def test_original_run_against_the_deleted_preview_is_still_accepted(self):
        """THE DECISION, PINNED SO IT CANNOT BE CHANGED SILENTLY (#1213 round 5).

        Preview `rjyboqwcdzcocqgmsyel` was deleted and rebuilt as
        `mvpkijzfmfcxhnzqogzs` on 2026-08-18. EVERY original apply run that exists
        therefore ran against the predecessor instance, so requiring the original
        run to bind to the current `PREVIEW_PROJECT_REF` would refuse one hundred
        percent of the recoveries this lane was built for, including the stranded
        Sample Tracking merges. It is deliberately not required.

        The residual is written down in `prove_historical_original_apply_runs`
        and in AGENTS.md: the ledger half of this lane may be satisfied by one
        database and the byte half by another. If that trade is ever reversed,
        this test is where the reversal is declared.
        """
        self.run_historical_prove_preview(
            original_instance=json.dumps({
                "schema": "shared-db-preview-instance-binding/v1",
                "previewProjectRef": "rjyboqwcdzcocqgmsyel",
            })
        )

    def test_workflow_refuses_both_historical_forms_at_once(self):
        """Two inputs describing one batch, one silently unused, is not a state
        a production gate should run in."""
        workflow = (Path(__file__).resolve().parents[1] / PREVIEW_WORKFLOW).read_text(encoding="utf-8")
        self.assertIn("REFUSED: name historical_preview_source_pr OR historical_preview_source_pr_map, not both.", workflow)

    def test_every_historical_condition_tests_both_forms(self):
        """Not substring presence: each historical-keyed condition must name BOTH
        inputs, or a map-authored recovery slips into the real apply path."""
        workflow = (Path(__file__).resolve().parents[1] / PREVIEW_WORKFLOW).read_text(encoding="utf-8")
        for line in workflow.splitlines():
            if "historical_preview_source_pr" not in line:
                continue
            if "description:" in line or line.strip().endswith(":"):
                continue
            if "==" in line or "!=" in line:
                self.assertIn("historical_preview_source_pr_map", line,
                              f"historical condition tests only the single-PR input: {line.strip()}")

    def classify(self, body):
        from production_business_risk_gate import classify_sql
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "supabase/migrations").mkdir(parents=True)
            (root / "supabase/migrations/20260814000000_x.sql").write_text(body, encoding="utf-8")
            return classify_sql(root, ["20260814000000"])

    def test_creating_new_tables_is_not_reported_as_losing_production_data(self):
        """The false alarm that turned the owner-decision block into a rubber stamp.

        Every clause here is ordinary idempotent table creation. None of it touches
        existing data, and the classifier used to report data loss AND downtime for
        all of it. That is what was being escalated to a non-programmer for sign-off.
        """
        sql = "; ".join([
            "CREATE TABLE IF NOT EXISTS dflow.a (id bigint PRIMARY KEY, b_fk integer REFERENCES dflow.b(id) ON UPDATE CASCADE ON DELETE RESTRICT)",
            "CREATE INDEX IF NOT EXISTS a_idx ON dflow.a (id)",
            "DROP TRIGGER IF EXISTS t ON dflow.a",
            "CREATE TRIGGER t BEFORE UPDATE ON dflow.a FOR EACH ROW EXECUTE FUNCTION dflow.f()",
        ]) + ";"
        reasons = self.classify(sql)
        self.assertNotIn(RISK_TEXT["permanent_data_rewrite_or_loss"], reasons)
        self.assertNotIn(RISK_TEXT["expected_downtime"], reasons)

    def test_a_function_body_does_not_make_the_migration_destructive(self):
        """A trigger body describes runtime behaviour, not the apply-time effect."""
        sql = ("CREATE OR REPLACE FUNCTION dflow.f() RETURNS trigger LANGUAGE plpgsql AS $$ "
               "BEGIN UPDATE dflow.a SET id = id; DELETE FROM dflow.b; RETURN NEW; END; $$;")
        self.assertNotIn(RISK_TEXT["permanent_data_rewrite_or_loss"], self.classify(sql))

    def test_genuinely_destructive_statements_are_still_reported(self):
        """Narrowing must not blind it. These are real and must still be seen."""
        for body, risk in [
            ("DROP TABLE dflow.a;", "permanent_data_rewrite_or_loss"),
            ("TRUNCATE dflow.a;", "permanent_data_rewrite_or_loss"),
            ("DELETE FROM dflow.a WHERE id > 0;", "permanent_data_rewrite_or_loss"),
            ("UPDATE dflow.a SET id = 1;", "permanent_data_rewrite_or_loss"),
            ("ALTER TABLE dflow.a ADD COLUMN c text;", "expected_downtime"),
            ("LOCK TABLE dflow.a IN SHARE MODE;", "expected_downtime"),
            ("CREATE UNIQUE INDEX a_u ON dflow.a (id);", "expected_downtime"),
            ("GRANT SELECT ON dflow.a TO authenticated;", "material_access_change"),
        ]:
            with self.subTest(body=body):
                self.assertIn(RISK_TEXT[risk], self.classify(body))

    def test_disclosed_risks_no_longer_block_promotion(self):
        """Owner ruling 2026-08-18: derived risks are DISCLOSED in the evidence,
        not used to demand a signature from someone who cannot evaluate them."""
        decision = decide_business_risk(
            [RISK_TEXT["material_access_change"]], recovery_proven=True, review_approved=True)
        self.assertFalse(decision["automaticPromotionAllowed"])
        self.assertEqual(decision["ownerDecisionReasons"], [RISK_TEXT["material_access_change"]])

    def test_legacy_author_check_waiver_is_exactly_pinned(self):
        args = [924, "5135b668d87c1639281c506ae75fde75211b7019", "96bf385aa5c0f703ec98f5730249f586964f5142", ["20260813210000", "20260813220000"]]
        self.assertTrue(is_pinned_historical_disney_source(*args))
        for changed in [
            [925, *args[1:]],
            [args[0], "a" * 40, *args[2:]],
            [*args[:2], "b" * 40, args[3]],
            [*args[:3], ["20260813210000"]],
        ]:
            self.assertFalse(is_pinned_historical_disney_source(*changed))


if __name__ == "__main__":
    unittest.main()
