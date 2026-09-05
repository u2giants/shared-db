-- Issue #2203 — contract tests for the completed DesignFlow workflow-action contract.
--
-- Migration: 20260905053422_workflow_action_handoff_integrity.sql
--
-- The required behavior comes from the issue: repeated pricing cycles return to the
-- right requester, stale transitions are rejected, a handoff cannot be returned
-- twice, a recipient-required transition with no recipient rolls everything back,
-- the original actor stays immutable behind a labeled fallback, and correlation-key
-- retries stay idempotent.
--
-- Everything below is invented and rolled back. CI replays every migration into an
-- EMPTY database, so no fixture may depend on a pre-existing row. Every literal is a
-- labelled synthetic value (issue-2203-*), never a real user, item or step.

begin;

do $test$
declare
  v_item integer;
  v_sales_a integer;
  v_sales_b integer;
  v_sourcing integer;
  v_admin integer;
  v_step_start integer;
  v_step_sourcing integer;
  v_step_sales integer;
  v_step_quality integer;
  v_handoff_1 bigint;
  v_return_1 bigint;
  v_handoff_2 bigint;
  v_return_2 bigint;
  v_handoff_3 bigint;
  v_return_3 bigint;
  v_retry bigint;
  v_actions_before bigint;
  v_notifications_before bigint;
  v_step_before integer;
  v_overloads integer;
begin
  -- ===================================================================================
  -- Fixtures.
  -- ===================================================================================
  insert into dflow.users(name,email) values
    ('Issue 2203 Sales A','issue-2203-sales-a@example.test'),
    ('Issue 2203 Sales B','issue-2203-sales-b@example.test'),
    ('Issue 2203 Sourcing','issue-2203-sourcing@example.test'),
    ('Issue 2203 Admin','issue-2203-admin@example.test');
  select id into v_sales_a from dflow.users where email = 'issue-2203-sales-a@example.test';
  select id into v_sales_b from dflow.users where email = 'issue-2203-sales-b@example.test';
  select id into v_sourcing from dflow.users where email = 'issue-2203-sourcing@example.test';
  select id into v_admin from dflow.users where email = 'issue-2203-admin@example.test';

  insert into plm."RFQStep"("RFQStep_title") values
    ('issue-2203-start'), ('issue-2203-sourcing'), ('issue-2203-sales'), ('issue-2203-quality');
  select "RFQStep_id" into v_step_start   from plm."RFQStep" where "RFQStep_title" = 'issue-2203-start';
  select "RFQStep_id" into v_step_sourcing from plm."RFQStep" where "RFQStep_title" = 'issue-2203-sourcing';
  select "RFQStep_id" into v_step_sales   from plm."RFQStep" where "RFQStep_title" = 'issue-2203-sales';
  select "RFQStep_id" into v_step_quality from plm."RFQStep" where "RFQStep_title" = 'issue-2203-quality';

  insert into plm."RFQItem"("rfqItem_step") values (v_step_start) returning "rfqItem_id" into v_item;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000a',
    'email','issue-2203-sales-a@example.test')::text, true);

  perform dflow.set_item_user_assignment(v_item,'sourcing',v_sourcing,true);

  -- ===================================================================================
  -- A. Exactly one record_item_workflow_action exists, on its original eleven-
  --    parameter signature. A second same-named function whose leading parameter
  --    types match would make every existing eleven-argument call ambiguous
  --    ("function is not unique") -- a production outage dressed up as backwards
  --    compatibility. Dropping the superseded one does not fix that either: the
  --    replay harness restores routine definitions around re-run migrations, so a
  --    dropped overload comes back. The new inputs therefore travel as reserved
  --    keys inside p_routing_context and the signature never changes.
  -- ===================================================================================
  select count(*)::integer into v_overloads
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'dflow' and p.proname = 'record_item_workflow_action';
  if v_overloads <> 1 then
    raise exception 'A FAILED: % record_item_workflow_action overloads exist; exactly one is required',
      v_overloads;
  end if;
  -- One signature, and it is still the ELEVEN-parameter one every existing caller
  -- compiles against. New inputs travel as reserved routing-context keys precisely
  -- so that no second overload can ever make an existing call ambiguous.
  if (select p.pronargs from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'dflow' and p.proname = 'record_item_workflow_action') <> 11 then
    raise exception 'A FAILED: the function signature changed; existing eleven-argument callers would break';
  end if;
  raise notice 'A PASSED: one unambiguous record_item_workflow_action.';

  -- ===================================================================================
  -- B. Cycle 1. Sales A hands off to Sourcing; the handoff is open; the return goes
  --    back to Sales A and carries an explicit source_action_id.
  -- ===================================================================================
  v_handoff_1 := dflow.record_item_workflow_action(
    v_item, v_step_sourcing, 'send_to_sourcing', 'a2203001-0000-4000-8000-000000000001',
    'sales', 'sourcing', false);

  if not (select is_open from dflow.item_workflow_handoff where handoff_action_id = v_handoff_1) then
    raise exception 'B FAILED: a fresh handoff is not reported open';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000b',
    'email','issue-2203-sourcing@example.test')::text, true);

  v_return_1 := dflow.record_item_workflow_action(
    v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-000000000002',
    'sourcing', 'sales', true);

  if (select source_action_id from dflow.item_workflow_action where id = v_return_1)
       is distinct from v_handoff_1 then
    raise exception 'B FAILED: the return did not link to the handoff it answers';
  end if;
  if (select user_id_fk from app.user_notification where workflow_action_id = v_return_1)
       <> v_sales_a then
    raise exception 'B FAILED: cycle 1 return did not reach Sales A';
  end if;
  if (select is_open from dflow.item_workflow_handoff where handoff_action_id = v_handoff_1) then
    raise exception 'B FAILED: an answered handoff is still reported open';
  end if;
  raise notice 'B PASSED: cycle 1 returns to its own requester and closes its handoff.';

  -- ===================================================================================
  -- C. THE DEFECT THIS ISSUE EXISTS FOR — cycle 2 by a DIFFERENT requester. The old
  --    function matched the EARLIEST reverse-direction handoff, so this return went
  --    to Sales A. It must go to Sales B.
  -- ===================================================================================
  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000c',
    'email','issue-2203-sales-b@example.test')::text, true);

  v_handoff_2 := dflow.record_item_workflow_action(
    v_item, v_step_sourcing, 'send_to_sourcing', 'a2203001-0000-4000-8000-000000000003',
    'sales', 'sourcing', false);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000b',
    'email','issue-2203-sourcing@example.test')::text, true);

  v_return_2 := dflow.record_item_workflow_action(
    v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-000000000004',
    'sourcing', 'sales', true);

  if (select source_action_id from dflow.item_workflow_action where id = v_return_2)
       is distinct from v_handoff_2 then
    raise exception 'C FAILED: cycle 2 return linked to the wrong handoff';
  end if;
  if (select user_id_fk from app.user_notification where workflow_action_id = v_return_2)
       <> v_sales_b then
    raise exception 'C FAILED: cycle 2 returned to the first cycle requester, not its own';
  end if;
  raise notice 'C PASSED: a second pricing cycle returns to its own requester.';

  -- ===================================================================================
  -- D. Duplicate return. Every handoff is now answered, so a third return has nothing
  --    open to close and is refused rather than silently reusing an answered handoff.
  -- ===================================================================================
  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-000000000005',
      'sourcing', 'sales', true);
    raise exception 'D FAILED: a duplicate return with no open handoff was accepted';
  exception when sqlstate 'P0002' then null;
  end;

  -- The rule is a database constraint, not a convention in the function: pointing a
  -- second row at an answered handoff is refused even by direct DML.
  begin
    insert into dflow.item_workflow_action(
      rfq_item_id, actor_user_id, actor_auth_user_id, prior_step_id, new_step_id,
      action_key, correlation_key, source_action_id)
    values (v_item, v_sourcing, 'a2203000-0000-4000-8000-00000000000b',
            v_step_sales, v_step_sales, 'return_to_sales',
            'a2203001-0000-4000-8000-000000000006', v_handoff_1);
    raise exception 'D FAILED: a second answer to one handoff was accepted by direct DML';
  exception when unique_violation then null;
  end;
  raise notice 'D PASSED: one handoff can be answered exactly once.';

  -- ===================================================================================
  -- E. Stale transition. A caller that read the item at an older step may not move it.
  -- ===================================================================================
  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000a',
    'email','issue-2203-sales-a@example.test')::text, true);

  select count(*) into v_actions_before from dflow.item_workflow_action;
  select "rfqItem_step" into v_step_before from plm."RFQItem" where "rfqItem_id" = v_item;

  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_sourcing, 'send_to_sourcing', 'a2203001-0000-4000-8000-000000000007',
      'sales', 'sourcing', false,
      'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
      jsonb_build_object('expected_prior_step_id', v_step_start));
    raise exception 'E FAILED: a stale transition from an old step was accepted';
  exception when sqlstate '40001' then null;
  end;

  if (select count(*) from dflow.item_workflow_action) <> v_actions_before then
    raise exception 'E FAILED: the rejected stale transition still wrote an action row';
  end if;
  if (select "rfqItem_step" from plm."RFQItem" where "rfqItem_id" = v_item)
       is distinct from v_step_before then
    raise exception 'E FAILED: the rejected stale transition still moved the item';
  end if;

  -- Positive control: the SAME call with the CORRECT expected prior step succeeds, so
  -- block E cannot pass because the guard rejects everything.
  v_handoff_3 := dflow.record_item_workflow_action(
    v_item, v_step_sourcing, 'send_to_sourcing', 'a2203001-0000-4000-8000-000000000008',
    'sales', 'sourcing', false,
    'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
    jsonb_build_object('expected_prior_step_id', v_step_before));
  if v_handoff_3 is null then
    raise exception 'E FAILED: the correct expected prior step was rejected too';
  end if;
  raise notice 'E PASSED: stale transitions are rejected and current ones are not.';

  -- ===================================================================================
  -- F. Retry idempotence survives the staleness guard. A retried call must return the
  --    same action even though the item has since moved past the step it was read at,
  --    and reuse by a different action is still refused.
  -- ===================================================================================
  v_retry := dflow.record_item_workflow_action(
    v_item, v_step_sourcing, 'send_to_sourcing', 'a2203001-0000-4000-8000-000000000008',
    'sales', 'sourcing', false,
    'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
    jsonb_build_object('expected_prior_step_id', v_step_before));
  if v_retry <> v_handoff_3 then
    raise exception 'F FAILED: a retried call created a second action';
  end if;

  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_quality, 'send_to_quality', 'a2203001-0000-4000-8000-000000000008',
      'sales', 'quality', false);
    raise exception 'F FAILED: a correlation key was reused for a different action';
  exception when sqlstate '23505' then null;
  end;
  raise notice 'F PASSED: retries are idempotent and correlation reuse is refused.';

  -- ===================================================================================
  -- G. Inactive original requester and the labeled fallback. The notification goes to
  --    the fallback; the record of WHO ASKED is never rewritten.
  -- ===================================================================================
  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000b',
    'email','issue-2203-sourcing@example.test')::text, true);

  v_return_3 := dflow.record_item_workflow_action(
    v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-000000000009',
    'sourcing', 'sales', true,
    'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
    jsonb_build_object('fallback_recipient_user_id', v_admin,
                       'fallback_reason', 'original requester is inactive'));

  if (select user_id_fk from app.user_notification where workflow_action_id = v_return_3)
       <> v_admin then
    raise exception 'G FAILED: the fallback recipient was not notified';
  end if;
  if (select original_actor_user_id from dflow.item_workflow_handoff
       where handoff_action_id = v_handoff_3) <> v_sales_a then
    raise exception 'G FAILED: the original requester was not preserved behind the fallback';
  end if;
  if not (select requires_admin_review from dflow.item_workflow_handoff
           where handoff_action_id = v_handoff_3) then
    raise exception 'G FAILED: a fallback did not raise admin review state';
  end if;
  if (select fallback_reason from dflow.item_workflow_handoff
       where handoff_action_id = v_handoff_3) <> 'original requester is inactive' then
    raise exception 'G FAILED: the fallback reason is not queryable';
  end if;

  -- The reserved keys are transport, not storage: they must not survive into the
  -- stored routing context, or the fallback facts would be free JSON again.
  if (select routing_context from dflow.item_workflow_action where id = v_return_3)
       ?| array['fallback_recipient_user_id','fallback_reason',
                'expected_prior_step_id','require_recipient'] then
    raise exception 'G FAILED: a reserved routing-context key was stored on the action row';
  end if;

  -- A malformed reserved key is refused rather than silently ignored -- a
  -- mistyped guard input must never quietly disable the guard.
  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-00000000000e',
      'sourcing', 'sales', true,
      'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
      jsonb_build_object('require_recipient', 'yes'));
    raise exception 'G FAILED: a non-boolean require_recipient was accepted';
  exception when sqlstate '22023' then null;
  end;

  -- An unlabeled fallback is refused: the reason may not be optional.
  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_sales, 'return_to_sales', 'a2203001-0000-4000-8000-00000000000a',
      'sourcing', 'sales', true,
      'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
      jsonb_build_object('fallback_recipient_user_id', v_admin));
    raise exception 'G FAILED: an unlabeled fallback was accepted';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'G PASSED: fallback is labeled, reviewable, and never rewrites the requester.';

  -- ===================================================================================
  -- H. Missing owner. A required handoff to a function with no active assignee must
  --    roll the whole transition back, not commit a step change nobody was told about.
  -- ===================================================================================
  select count(*) into v_actions_before from dflow.item_workflow_action;
  select count(*) into v_notifications_before from app.user_notification;
  select "rfqItem_step" into v_step_before from plm."RFQItem" where "rfqItem_id" = v_item;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','a2203000-0000-4000-8000-00000000000a',
    'email','issue-2203-sales-a@example.test')::text, true);

  begin
    perform dflow.record_item_workflow_action(
      v_item, v_step_quality, 'send_to_quality', 'a2203001-0000-4000-8000-00000000000b',
      'sales', 'quality', false);
    raise exception 'H FAILED: a required handoff committed with zero recipients';
  exception when sqlstate 'P0002' then null;
  end;

  if (select count(*) from dflow.item_workflow_action) <> v_actions_before then
    raise exception 'H FAILED: the zero-recipient handoff left an action row behind';
  end if;
  if (select count(*) from app.user_notification) <> v_notifications_before then
    raise exception 'H FAILED: the zero-recipient handoff left a notification behind';
  end if;
  if (select "rfqItem_step" from plm."RFQItem" where "rfqItem_id" = v_item)
       is distinct from v_step_before then
    raise exception 'H FAILED: the zero-recipient handoff still moved the item';
  end if;

  -- Positive control 1: the same handoff succeeds once an assignee exists.
  perform dflow.set_item_user_assignment(v_item,'quality',v_admin,true);
  if dflow.record_item_workflow_action(
       v_item, v_step_quality, 'send_to_quality', 'a2203001-0000-4000-8000-00000000000c',
       'sales', 'quality', false) is null then
    raise exception 'H FAILED: a handoff with an active assignee was still refused';
  end if;

  -- Positive control 2: a caller that deliberately opts out still gets the old
  -- fire-and-forget behavior, so the guard is a contract and not a blanket block.
  perform dflow.set_item_user_assignment(v_item,'quality',v_admin,false);
  if dflow.record_item_workflow_action(
       v_item, v_step_quality, 'send_to_quality', 'a2203001-0000-4000-8000-00000000000d',
       'sales', 'quality', false,
       'workflow', 'RFQ workflow update', 'An RFQ item needs your attention',
       jsonb_build_object('require_recipient', false)) is null then
    raise exception 'H FAILED: an explicitly non-required handoff was refused';
  end if;
  raise notice 'H PASSED: recipient-required transitions roll back; opt-out still works.';

  -- ===================================================================================
  -- I. Access. The new view must not be reachable by anon, and the function must keep
  --    its pinned search_path.
  -- ===================================================================================
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'anon') then
    if has_table_privilege('anon','dflow.item_workflow_handoff','SELECT') then
      raise exception 'I FAILED: anon can read the handoff view';
    end if;
  end if;
  if exists (
    select 1
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'dflow' and p.proname = 'record_item_workflow_action'
       and not exists (
         select 1 from unnest(coalesce(p.proconfig, array[]::text[])) c
          where c like 'search_path=%')
  ) then
    raise exception 'I FAILED: record_item_workflow_action does not pin search_path';
  end if;
  raise notice 'I PASSED: access and search_path pinning hold.';
end
$test$;

rollback;
