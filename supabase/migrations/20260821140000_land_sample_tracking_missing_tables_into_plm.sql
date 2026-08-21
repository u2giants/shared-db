-- Land the sample-tracking tables that exist only in dflow into plm as dual
-- copies. Does NOT SET SCHEMA / drop dflow (segregation.md runtime gotcha +
-- 20260721201500 restore: designflow-tracking still calls dflow.post_sample_movement).
--
-- Steps:
--   1) Bring plm base sample tables up to the dflow column contract and backfill rows.
--   2) CREATE the five missing tables in plm (LIKE dflow INCLUDING ALL).
--   3) Wire FKs to plm parents (not dflow).
--   4) Copy rows and advance identity sequences.
--
-- Preview / develop first. Production main is unchanged by this apply.

set lock_timeout = '5s';
set statement_timeout = '10min';

-- ---------------------------------------------------------------------------
-- 1) Column parity on existing plm sample base tables
-- ---------------------------------------------------------------------------
alter table plm.sample
  add column if not exists quantity_migration_state text not null default 'unknown';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_quantity_migration_state_check'
      and conrelid = 'plm.sample'::regclass
  ) then
    alter table plm.sample
      add constraint sample_quantity_migration_state_check
      check (quantity_migration_state = any (array['unknown'::text, 'known'::text, 'reconciled'::text]));
  end if;
end $$;

alter table plm.sample_box
  add column if not exists owner_factory_id_fk integer,
  add column if not exists ownership_state text not null default 'unassigned';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_box_ownership_state_check'
      and conrelid = 'plm.sample_box'::regclass
  ) then
    alter table plm.sample_box
      add constraint sample_box_ownership_state_check
      check (ownership_state = any (array['owned'::text, 'internal'::text, 'ambiguous'::text, 'unassigned'::text]));
  end if;
end $$;

alter table plm.sample_shipment_item
  add column if not exists quantity_intended integer;

-- ---------------------------------------------------------------------------
-- 2) Backfill empty plm base sample rows from dflow (FK order)
-- ---------------------------------------------------------------------------
insert into plm.sample_factory_group
select d.*
from dflow.sample_factory_group d
where not exists (
  select 1 from plm.sample_factory_group p where p.factory_group_id_pk = d.factory_group_id_pk
);

insert into plm.sample_box
select d.*
from dflow.sample_box d
where not exists (
  select 1 from plm.sample_box p where p.box_id_pk = d.box_id_pk
);

insert into plm.sample
select d.*
from dflow.sample d
where not exists (
  select 1 from plm.sample p where p.sample_id_pk = d.sample_id_pk
);

insert into plm.sample_event
select d.*
from dflow.sample_event d
where not exists (
  select 1 from plm.sample_event p where p.event_id_pk = d.event_id_pk
);

insert into plm.sample_comments
select d.*
from dflow.sample_comments d
where not exists (
  select 1 from plm.sample_comments p where p.id = d.id
);

insert into plm.sample_attachment
select d.*
from dflow.sample_attachment d
where not exists (
  select 1 from plm.sample_attachment p where p.sample_attachment_id = d.sample_attachment_id
);

insert into plm.sample_shipment_item
select d.*
from dflow.sample_shipment_item d
where not exists (
  select 1 from plm.sample_shipment_item p where p.shipment_item_id_pk = d.shipment_item_id_pk
);

-- ---------------------------------------------------------------------------
-- 3) Create the five missing plm tables (structure only; LIKE skips FKs)
-- ---------------------------------------------------------------------------
create table if not exists plm.sample_import_job
  (like dflow.sample_import_job including all);

create table if not exists plm.sample_import_row
  (like dflow.sample_import_row including all);

create table if not exists plm.sample_shipment_line
  (like dflow.sample_shipment_line including all);

create table if not exists plm.sample_movement
  (like dflow.sample_movement including all);

create table if not exists plm.sample_stop_closeout
  (like dflow.sample_stop_closeout including all);

-- ---------------------------------------------------------------------------
-- 4) FKs onto plm parents
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_import_row_import_job_id_fkey'
      and conrelid = 'plm.sample_import_row'::regclass
  ) then
    alter table plm.sample_import_row
      add constraint sample_import_row_import_job_id_fkey
      foreign key (import_job_id) references plm.sample_import_job (import_job_id)
      on update cascade on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_import_row_resulting_box_id_fkey'
      and conrelid = 'plm.sample_import_row'::regclass
  ) then
    alter table plm.sample_import_row
      add constraint sample_import_row_resulting_box_id_fkey
      foreign key (resulting_box_id) references plm.sample_box (box_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_import_row_resulting_sample_id_fkey'
      and conrelid = 'plm.sample_import_row'::regclass
  ) then
    alter table plm.sample_import_row
      add constraint sample_import_row_resulting_sample_id_fkey
      foreign key (resulting_sample_id) references plm.sample (sample_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_shipment_line_box_id_fk_fkey'
      and conrelid = 'plm.sample_shipment_line'::regclass
  ) then
    alter table plm.sample_shipment_line
      add constraint sample_shipment_line_box_id_fk_fkey
      foreign key (box_id_fk) references plm.sample_box (box_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_shipment_line_sample_id_fk_fkey'
      and conrelid = 'plm.sample_shipment_line'::regclass
  ) then
    alter table plm.sample_shipment_line
      add constraint sample_shipment_line_sample_id_fk_fkey
      foreign key (sample_id_fk) references plm.sample (sample_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_movement_box_id_fk_fkey'
      and conrelid = 'plm.sample_movement'::regclass
  ) then
    alter table plm.sample_movement
      add constraint sample_movement_box_id_fk_fkey
      foreign key (box_id_fk) references plm.sample_box (box_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_movement_sample_id_fk_fkey'
      and conrelid = 'plm.sample_movement'::regclass
  ) then
    alter table plm.sample_movement
      add constraint sample_movement_sample_id_fk_fkey
      foreign key (sample_id_fk) references plm.sample (sample_id_pk)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_movement_shipment_line_id_fkey'
      and conrelid = 'plm.sample_movement'::regclass
  ) then
    alter table plm.sample_movement
      add constraint sample_movement_shipment_line_id_fkey
      foreign key (shipment_line_id) references plm.sample_shipment_line (shipment_line_id)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_movement_reversal_of_movement_id_fkey'
      and conrelid = 'plm.sample_movement'::regclass
  ) then
    alter table plm.sample_movement
      add constraint sample_movement_reversal_of_movement_id_fkey
      foreign key (reversal_of_movement_id) references plm.sample_movement (movement_id)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_stop_closeout_movement_watermark_fkey'
      and conrelid = 'plm.sample_stop_closeout'::regclass
  ) then
    alter table plm.sample_stop_closeout
      add constraint sample_stop_closeout_movement_watermark_fkey
      foreign key (movement_watermark) references plm.sample_movement (movement_id)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_stop_closeout_reopens_closeout_id_fkey'
      and conrelid = 'plm.sample_stop_closeout'::regclass
  ) then
    alter table plm.sample_stop_closeout
      add constraint sample_stop_closeout_reopens_closeout_id_fkey
      foreign key (reopens_closeout_id) references plm.sample_stop_closeout (closeout_id)
      on update cascade on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'sample_stop_closeout_sample_id_fk_fkey'
      and conrelid = 'plm.sample_stop_closeout'::regclass
  ) then
    alter table plm.sample_stop_closeout
      add constraint sample_stop_closeout_sample_id_fk_fkey
      foreign key (sample_id_fk) references plm.sample (sample_id_pk)
      on update cascade on delete restrict;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5) Copy the five table bodies
-- ---------------------------------------------------------------------------
insert into plm.sample_import_job
select d.*
from dflow.sample_import_job d
where not exists (
  select 1 from plm.sample_import_job p where p.import_job_id = d.import_job_id
);

insert into plm.sample_import_row
select d.*
from dflow.sample_import_row d
where not exists (
  select 1 from plm.sample_import_row p where p.import_row_id = d.import_row_id
);

insert into plm.sample_shipment_line
select d.*
from dflow.sample_shipment_line d
where not exists (
  select 1 from plm.sample_shipment_line p where p.shipment_line_id = d.shipment_line_id
);

insert into plm.sample_movement
select d.*
from dflow.sample_movement d
where not exists (
  select 1 from plm.sample_movement p where p.movement_id = d.movement_id
);

insert into plm.sample_stop_closeout
select d.*
from dflow.sample_stop_closeout d
where not exists (
  select 1 from plm.sample_stop_closeout p where p.closeout_id = d.closeout_id
);

-- ---------------------------------------------------------------------------
-- 6) Advance identity sequences so new inserts do not collide
-- ---------------------------------------------------------------------------
do $$
declare
  seq text;
  max_id bigint;
begin
  foreach seq in array array[
    'plm.sample_factory_group.factory_group_id_pk',
    'plm.sample_box.box_id_pk',
    'plm.sample.sample_id_pk',
    'plm.sample_event.event_id_pk',
    'plm.sample_comments.id',
    'plm.sample_attachment.sample_attachment_id',
    'plm.sample_shipment_item.shipment_item_id_pk',
    'plm.sample_import_job.import_job_id',
    'plm.sample_import_row.import_row_id',
    'plm.sample_shipment_line.shipment_line_id',
    'plm.sample_movement.movement_id',
    'plm.sample_stop_closeout.closeout_id'
  ]
  loop
    execute format(
      'select coalesce(max(%I), 0) from %I.%I',
      split_part(seq, '.', 3),
      split_part(seq, '.', 1),
      split_part(seq, '.', 2)
    ) into max_id;
    perform setval(
      pg_get_serial_sequence(
        format('%I.%I', split_part(seq, '.', 1), split_part(seq, '.', 2)),
        split_part(seq, '.', 3)
      ),
      greatest(max_id, 1),
      max_id > 0
    );
  end loop;
end $$;
