Perform an independent read-only final review of u2giants/shared-db issue #1467 and PR #1585 at exact head 9cc3f4c735ca2778e074f0e3872e9c8924b527d4.

Read AGENTS.md, the issue/PR context available in the repository, and the exact diff from its merge base. Verify that the forward migration safely removes only the temporary asset-tags normalization index after the prerequisite normalization became structurally enforced. Pay particular attention to dependency evidence, migration ordering, object qualification, idempotence, capability preservation, and whether dropping this index could remove a still-needed query or write-path capability. Do not expose row data or secrets. Do not edit files or run commands.

Return APPROVE or REVISE. For every Critical, High, or Medium finding, cite the exact file and line and explain the concrete failure. Separate proven defects from optional improvements. State the exact head reviewed.
