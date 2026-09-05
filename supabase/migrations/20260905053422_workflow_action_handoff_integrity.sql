-- #2203: complete the DesignFlow workflow-action contract.
-- derived-from: 20260904143518
--
-- Three defects in the applied #1987/#2202 contract are closed here:
--
--  1. A return action was matched to the EARLIEST reverse-direction action on
--     the item, so the second and every later pricing cycle returned to the
--     first cycle's requester. A return now carries an explicit self-FK
--     (source_action_id) to the exact handoff it closes, and the function
--     selects the LATEST still-open handoff. "Open" means no other action
--     already points at it, enforced by a partial unique index rather than by
--     convention, so one handoff can never be returned twice.
--
--  2. The function accepted no expected prior step, so a stale browser could
--     overwrite a newer transition once it won the item lock. An optional
--     p_expected_prior_step_id is compared under the same FOR UPDATE lock and
--     BEFORE any write; a mismatch raises 40001 so the caller can refetch and
--     retry.
--
--  3. A required handoff could commit its step change with zero notifications
--     when the destination function had no active assignee. Recipient-required
--     transitions now count what they inserted and raise, rolling the whole
--     transaction back, when nothing resolved.
--
-- Fallback facts stop being free JSON: fallback_recipient_user_id,
-- fallback_reason and requires_admin_review are real, queryable columns. The
-- ORIGINAL actor is never rewritten -- it is always read back through
-- source_action_id -- so a labeled inactive-requester or legacy fallback
-- changes only who is notified, never who the record says asked.
--
-- The #1987 migration is not edited. dflow.item_workflow_action rows remain
-- append-only (the #1987 trigger rejects every UPDATE and DELETE), which is why
-- the "handoff is closed" fact is modelled as a child row pointing back at its
-- parent rather than as a flag updated on the parent.

set lock_timeout = '5s';
set statement_timeout = '5min';

-- ---------------------------------------------------------------- structure --

alter table dflow.item_workflow_action
  add column if not exists source_action_id bigint,
  add column if not exists fallback_recipient_user_id integer,
  add column if not exists fallback_reason text,
  add column if not exists requires_admin_review boolean not null default false;

alter table dflow.item_workflow_action
  drop constraint if exists item_workflow_action_source_action_id_fkey,
  add constraint item_workflow_action_source_action_id_fkey
    foreign key (source_action_id) references dflow.item_workflow_action(id)
    on delete restrict;

alter table dflow.item_workflow_action
  drop constraint if exists item_workflow_action_fallback_recipient_fkey,
  add constraint item_workflow_action_fallback_recipient_fkey
    foreign key (fallback_recipient_user_id) references dflow.users(id);

alter table dflow.item_workflow_action
  drop constraint if exists item_workflow_action_source_action_not_self,
  add constraint item_workflow_action_source_action_not_self
    check (source_action_id is null or source_action_id <> id);

-- A fallback is only meaningful on an action that names the handoff it is
-- answering, and a labeled fallback must always carry its reason.
alter table dflow.item_workflow_action
  drop constraint if exists item_workflow_action_fallback_is_labeled,
  add constraint item_workflow_action_fallback_is_labeled
    check (
      (fallback_recipient_user_id is null and fallback_reason is null)
      or (fallback_recipient_user_id is not null
          and fallback_reason is not null
          and btrim(fallback_reason) <> ''
          and source_action_id is not null)
    );

-- The open/closed handoff rule, enforced rather than assumed: at most one
-- action may close any given source handoff. Repeated pricing cycles are
-- therefore unambiguous -- each cycle's handoff is closed by exactly one
-- return, and the next cycle opens a new handoff of its own. A deliberate
-- reversal would have to be modelled as its own action type; it may not reuse
-- an already-answered handoff.
create unique index if not exists item_workflow_action_one_return_per_source
  on dflow.item_workflow_action (source_action_id)
  where source_action_id is not null;

-- Supports "the latest still-open handoff on this item in this direction".
create index if not exists item_workflow_action_open_handoff_lookup
  on dflow.item_workflow_action (rfq_item_id, occurred_at desc, id desc)
  include (actor_user_id);

create index if not exists item_workflow_action_admin_review
  on dflow.item_workflow_action (rfq_item_id, occurred_at)
  where requires_admin_review;

-- ----------------------------------------------------------------- read API --

-- Queryable open-handoff state for the read APIs and for tests: one row per
-- handoff action, with the return that closed it (NULL while still open).
create or replace view dflow.item_workflow_handoff as
select
  a.id                          as handoff_action_id,
  a.rfq_item_id,
  a.actor_user_id               as original_actor_user_id,
  a.occurred_at                 as handed_off_at,
  a.routing_context ->> 'from_function_key' as from_function_key,
  a.routing_context ->> 'to_function_key'   as to_function_key,
  r.id                          as return_action_id,
  r.actor_user_id               as returned_by_user_id,
  r.occurred_at                 as returned_at,
  r.fallback_recipient_user_id,
  r.fallback_reason,
  coalesce(r.requires_admin_review, false) as requires_admin_review,
  (r.id is null)                as is_open
from dflow.item_workflow_action a
left join dflow.item_workflow_action r
       on r.source_action_id = a.id
where a.routing_context ->> 'to_function_key' is not null;

revoke all on dflow.item_workflow_handoff from anon, authenticated;
grant select on dflow.item_workflow_handoff to authenticated, service_role;

-- ----------------------------------------------------------------- function --

-- The four new parameters all carry defaults, so every existing eleven-argument
-- call site keeps compiling. The old function is DROPPED rather than left
-- beside the new one on purpose: two functions of the same name whose first
-- eleven parameter types are identical make an eleven-argument call ambiguous
-- ("function is not unique") and would break every in-flight caller instead of
-- carrying it forward.
drop function if exists dflow.record_item_workflow_action(
  integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb
);

create or replace function dflow.record_item_workflow_action(
  p_rfq_item_id integer,
  p_new_step_id integer,
  p_action_key text,
  p_correlation_key uuid,
  p_from_function_key text default null,
  p_to_function_key text default null,
  p_return_to_original_handoff boolean default false,
  p_notification_type text default 'workflow',
  p_notification_title text default 'RFQ workflow update',
  p_notification_message text default 'An RFQ item needs your attention',
  p_routing_context jsonb default '{}'::jsonb,
  p_expected_prior_step_id integer default null,
  p_require_recipient boolean default true,
  p_fallback_recipient_user_id integer default null,
  p_fallback_reason text default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, dflow, auth
as $function$
declare
  v_actor integer := dflow.current_designflow_user_id();
  v_auth_actor uuid := auth.uid();
  v_prior_step integer;
  v_action_id bigint;
  v_existing dflow.item_workflow_action%rowtype;
  v_from text := lower(nullif(btrim(p_from_function_key), ''));
  v_to text := lower(nullif(btrim(p_to_function_key), ''));
  v_context jsonb;
  v_source_action_id bigint;
  v_original_actor integer;
  v_recipient integer;
  v_fallback_reason text := nullif(btrim(p_fallback_reason), '');
  v_notified integer;
begin
  if p_correlation_key is null then
    raise exception 'correlation key is required' using errcode = '22004';
  end if;
  if p_action_key is null or lower(btrim(p_action_key)) !~ '^[a-z][a-z0-9_-]*$' then
    raise exception 'action key is invalid' using errcode = '22023';
  end if;
  if p_routing_context is null or jsonb_typeof(p_routing_context) <> 'object' then
    raise exception 'routing context must be a JSON object' using errcode = '22023';
  end if;
  if p_return_to_original_handoff and (v_from is null or v_to is null) then
    raise exception 'return routing requires from and to function keys' using errcode = '22023';
  end if;
  if p_fallback_recipient_user_id is not null then
    if not p_return_to_original_handoff then
      raise exception 'a fallback recipient is only valid on a return to the original handoff'
        using errcode = '22023';
    end if;
    if v_fallback_reason is null then
      raise exception 'a fallback recipient requires a fallback reason' using errcode = '22023';
    end if;
  elsif v_fallback_reason is not null then
    raise exception 'a fallback reason requires a fallback recipient' using errcode = '22023';
  end if;

  -- Retry idempotence comes first: a retried call must succeed even though the
  -- item has since moved on, so it is answered before the staleness check.
  select * into v_existing
    from dflow.item_workflow_action
   where correlation_key = p_correlation_key;
  if found then
    if v_existing.rfq_item_id <> p_rfq_item_id
       or v_existing.new_step_id <> p_new_step_id
       or v_existing.action_key <> lower(btrim(p_action_key))
       or v_existing.actor_user_id <> v_actor then
      raise exception 'correlation key was already used for a different action' using errcode = '23505';
    end if;
    return v_existing.id;
  end if;

  select i."rfqItem_step" into v_prior_step
    from plm."RFQItem" i
   where i."rfqItem_id" = p_rfq_item_id
   for update;
  if not found then
    raise exception 'RFQ item % does not exist', p_rfq_item_id using errcode = '23503';
  end if;

  -- Stale-write rejection, under the item lock and before any write. A caller
  -- that read the item at step X may only move it from step X.
  if p_expected_prior_step_id is not null
     and v_prior_step is distinct from p_expected_prior_step_id then
    raise exception
      'RFQ item % moved to step % since it was read at step %; refetch and retry',
      p_rfq_item_id, v_prior_step, p_expected_prior_step_id
      using errcode = '40001';
  end if;

  perform 1 from plm."RFQStep" s where s."RFQStep_id" = p_new_step_id;
  if not found then
    raise exception 'RFQ step % does not exist', p_new_step_id using errcode = '23503';
  end if;

  -- Resolve the handoff being answered BEFORE writing anything, so a return
  -- with no open handoff never leaves a partial transition behind.
  if p_return_to_original_handoff then
    select a.id, a.actor_user_id
      into v_source_action_id, v_original_actor
      from dflow.item_workflow_action a
     where a.rfq_item_id = p_rfq_item_id
       and a.routing_context ->> 'from_function_key' = v_to
       and a.routing_context ->> 'to_function_key' = v_from
       and not exists (
             select 1
               from dflow.item_workflow_action r
              where r.source_action_id = a.id
           )
     order by a.occurred_at desc, a.id desc
     limit 1;

    if v_source_action_id is null then
      raise exception 'no open % to % handoff exists for RFQ item %', v_to, v_from, p_rfq_item_id
        using errcode = 'P0002';
    end if;

    -- The original actor is immutable and always read back from the source
    -- action. A fallback changes only who is notified.
    v_recipient := coalesce(p_fallback_recipient_user_id, v_original_actor);

    perform 1 from dflow.users u where u.id = v_recipient;
    if not found then
      raise exception 'DesignFlow user % does not exist', v_recipient using errcode = '23503';
    end if;
  end if;

  v_context := p_routing_context || jsonb_strip_nulls(jsonb_build_object(
    'from_function_key', v_from,
    'to_function_key', v_to,
    'return_to_original_handoff', p_return_to_original_handoff
  ));

  insert into dflow.item_workflow_action(
    rfq_item_id, actor_user_id, actor_auth_user_id, prior_step_id, new_step_id,
    action_key, correlation_key, routing_context,
    source_action_id, fallback_recipient_user_id, fallback_reason, requires_admin_review
  ) values (
    p_rfq_item_id, v_actor, v_auth_actor, v_prior_step, p_new_step_id,
    lower(btrim(p_action_key)), p_correlation_key, v_context,
    v_source_action_id, p_fallback_recipient_user_id, v_fallback_reason,
    p_fallback_recipient_user_id is not null
  )
  on conflict (correlation_key) do nothing
  returning id into v_action_id;

  if v_action_id is null then
    select * into v_existing
      from dflow.item_workflow_action
     where correlation_key = p_correlation_key;
    if not found
       or v_existing.rfq_item_id <> p_rfq_item_id
       or v_existing.new_step_id <> p_new_step_id
       or v_existing.action_key <> lower(btrim(p_action_key))
       or v_existing.actor_user_id <> v_actor then
      raise exception 'correlation key was already used for a different action' using errcode = '23505';
    end if;
    return v_existing.id;
  end if;

  update plm."RFQItem"
     set "rfqItem_step" = p_new_step_id,
         "rfqItem_date_modified" = clock_timestamp()
   where "rfqItem_id" = p_rfq_item_id;

  if p_return_to_original_handoff then
    insert into app.user_notification(
      type, created_date, event, unread, message, title, user_id_fk,
      workflow_action_id, idempotency_key
    ) values (
      p_notification_type, current_date, lower(btrim(p_action_key)), true,
      p_notification_message, p_notification_title, v_recipient,
      v_action_id, p_correlation_key::text || ':' || v_recipient::text
    ) on conflict (workflow_action_id, user_id_fk) where workflow_action_id is not null do nothing;
    get diagnostics v_notified = row_count;
  elsif v_to is not null then
    insert into app.user_notification(
      type, created_date, event, unread, message, title, user_id_fk,
      workflow_action_id, idempotency_key
    )
    select p_notification_type, current_date, lower(btrim(p_action_key)), true,
           p_notification_message, p_notification_title, a.user_id,
           v_action_id, p_correlation_key::text || ':' || a.user_id::text
      from dflow.item_user_assignment a
     where a.rfq_item_id = p_rfq_item_id
       and a.function_key = v_to
       and a.effective_to is null
    on conflict (workflow_action_id, user_id_fk) where workflow_action_id is not null do nothing;
    get diagnostics v_notified = row_count;
  else
    v_notified := 0;
  end if;

  -- A handoff that names a destination function is a required transition: it
  -- must not commit with nobody told. Raising here rolls back the action row,
  -- the item step change and the notification attempt together.
  if p_require_recipient and v_to is not null and coalesce(v_notified, 0) = 0 then
    raise exception
      'no eligible active recipient in function % for RFQ item %; transition rolled back',
      v_to, p_rfq_item_id
      using errcode = 'P0002';
  end if;

  return v_action_id;
end
$function$;

revoke all on function dflow.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb,integer,boolean,integer,text) from public;
grant execute on function dflow.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb,integer,boolean,integer,text) to authenticated, service_role;

comment on function dflow.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb,integer,boolean,integer,text) is
  'Records one immutable RFQ workflow action. Rejects stale transitions against p_expected_prior_step_id, links a return to the latest OPEN handoff via source_action_id, and rolls back a recipient-required transition that resolves nobody.';
comment on column dflow.item_workflow_action.source_action_id is
  'The handoff action this action answers. At most one action may answer any handoff, which is what makes a handoff open or closed across repeated pricing cycles.';
comment on column dflow.item_workflow_action.fallback_recipient_user_id is
  'Who was notified INSTEAD of the original requester. The original requester is never rewritten; read it through source_action_id.';
comment on column dflow.item_workflow_action.fallback_reason is
  'Why the original requester could not be notified (inactive user, legacy unattributed handoff). Required whenever a fallback recipient is set.';
comment on column dflow.item_workflow_action.requires_admin_review is
  'True when a fallback was used, so administrators can query the actions that did not reach their original requester.';
comment on view dflow.item_workflow_handoff is
  'One row per handoff action with the return that closed it. is_open drives the open/closed handoff rule for repeated pricing cycles.';
