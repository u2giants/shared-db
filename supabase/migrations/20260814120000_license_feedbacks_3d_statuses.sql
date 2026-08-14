-- 3D licensing statuses after Concept Approved.
-- POP: 3D Submitted, 3D Resubmitted
-- Licensor: 3D Not Approved at All, 3D Needs Revisions, 3D Approved with Revisions

INSERT INTO dflow."LicenseFeedBacks"
  (phase, status, explanation, duplicable, "order", access, item_order)
VALUES
  ('Phase 1.1 - 3D Approval', '3D Submitted', '3D files are submitted to the licensor for approval.', false, '7', 'POP', 7),
  ('Phase 1.1 - 3D Approval', '3D Resubmitted', 'Revised 3D files are submitted to the licensor. This can happen more than once.', true, '8', 'POP', 8),
  ('Phase 1.1 - 3D Approval', '3D Not Approved at All', 'The licensor outright rejects the 3D submission.', false, '9', 'Licensor', 9),
  ('Phase 1.1 - 3D Approval', '3D Needs Revisions', 'Licensor requests changes to the 3D submission. This can happen more than once.', true, '10', 'Licensor', 10),
  ('Phase 1.1 - 3D Approval', '3D Approved with Revisions', '3D is approved, but minor revisions must be made before proceeding.', false, '11', 'Licensor', 11);

INSERT INTO plm."LicenseFeedBacks"
  (phase, status, explanation, duplicable, "order", access, item_order)
VALUES
  ('Phase 1.1 - 3D Approval', '3D Submitted', '3D files are submitted to the licensor for approval.', false, '7', 'POP', 7),
  ('Phase 1.1 - 3D Approval', '3D Resubmitted', 'Revised 3D files are submitted to the licensor. This can happen more than once.', true, '8', 'POP', 8),
  ('Phase 1.1 - 3D Approval', '3D Not Approved at All', 'The licensor outright rejects the 3D submission.', false, '9', 'Licensor', 9),
  ('Phase 1.1 - 3D Approval', '3D Needs Revisions', 'Licensor requests changes to the 3D submission. This can happen more than once.', true, '10', 'Licensor', 10),
  ('Phase 1.1 - 3D Approval', '3D Approved with Revisions', '3D is approved, but minor revisions must be made before proceeding.', false, '11', 'Licensor', 11);
