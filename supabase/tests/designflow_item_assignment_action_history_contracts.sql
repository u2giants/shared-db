begin;

do $test$
declare
  v_item integer;
  v_sales integer;
  v_sourcing integer;
  v_step_old integer;
  v_step_sourcing integer;
  v_step_sales integer;
  v_first bigint;
  v_retry bigint;
  v_return bigint;
begin
  insert into dflow.users(name,email) values
    ('Issue 1987 Sales','issue-1987-sales@example.test'),
    ('Issue 1987 Sourcing','issue-1987-sourcing@example.test');
  select id into v_sales from dflow.users where email = 'issue-1987-sales@example.test';
  select id into v_sourcing from dflow.users where email = 'issue-1987-sourcing@example.test';

  insert into dflow."RFQStep"("RFQStep_title") values
    ('issue-1987-old'), ('@sourcing'), ('px sent to sales');
  select "RFQStep_id" into v_step_old from dflow."RFQStep" where "RFQStep_title" = 'issue-1987-old';
  select "RFQStep_id" into v_step_sourcing from dflow."RFQStep" where "RFQStep_title" = '@sourcing';
  select "RFQStep_id" into v_step_sales from dflow."RFQStep" where "RFQStep_title" = 'px sent to sales';

  insert into dflow."RFQItem"("rfqItem_step") values (v_step_old) returning "rfqItem_id" into v_item;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','11111111-1111-4111-8111-111111111111',
    'email','issue-1987-sales@example.test')::text, true);

  perform dflow.set_item_user_assignment(v_item,'sales',v_sales,true);
  perform dflow.set_item_user_assignment(v_item,'sourcing',v_sourcing,true);

  v_first := dflow.record_item_workflow_action(
    v_item,v_step_sourcing,'send_to_sourcing','11111111-1111-4111-8111-111111111112',
    'sales','sourcing',false
  );
  v_retry := dflow.record_item_workflow_action(
    v_item,v_step_sourcing,'send_to_sourcing','11111111-1111-4111-8111-111111111112',
    'sales','sourcing',false
  );
  if v_retry <> v_first then raise exception 'idempotent retry returned a new action'; end if;
  if (select count(*) from dflow.user_notification where workflow_action_id = v_first) <> 1 then
    raise exception 'sourcing action did not notify exactly the assigned sourcing user';
  end if;
  if (select user_id_fk from dflow.user_notification where workflow_action_id = v_first) <> v_sourcing then
    raise exception 'sourcing action notified the wrong user';
  end if;

  perform dflow.set_item_user_assignment(v_item,'sales',v_sales,false);

  perform set_config('request.jwt.claims', jsonb_build_object(
    'role','authenticated','sub','22222222-2222-4222-8222-222222222222',
    'email','issue-1987-sourcing@example.test')::text, true);
  v_return := dflow.record_item_workflow_action(
    v_item,v_step_sales,'return_to_sales','22222222-2222-4222-8222-222222222223',
    'sourcing','sales',true
  );
  if (select user_id_fk from dflow.user_notification where workflow_action_id = v_return) <> v_sales then
    raise exception 'return action did not preserve the original sales sender';
  end if;

  begin
    update dflow.item_workflow_action set action_key = 'rewritten' where id = v_first;
    raise exception 'workflow action rewrite was accepted';
  exception when sqlstate '55000' then null;
  end;
end
$test$;

rollback;
