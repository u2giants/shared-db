-- Issue #1352. Additive structure only; this migration copies no rows.
set lock_timeout='5s';
set statement_timeout='10min';

CREATE SCHEMA dflow_prod;
CREATE SCHEMA dflow_archive;

-- Freeze the 96 non-Sample tables from the current canonical dflow contract.
-- The count gate below fails closed if a future source surface would expand it.
DO $ddl$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.tables
    WHERE table_schema='dflow' AND table_type='BASE TABLE'
      AND table_name NOT LIKE 'sample%'
    ORDER BY table_name
  LOOP
    EXECUTE format('CREATE TABLE dflow_prod.%I (LIKE dflow.%I INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING IDENTITY INCLUDING STORAGE INCLUDING COMMENTS)',r.table_name,r.table_name);
  END LOOP;

  FOR r IN
    SELECT c.conname,c.conrelid::regclass::text AS rel,pg_get_constraintdef(c.oid,true) AS def
    FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='dflow' AND t.relname NOT LIKE 'sample%'
      AND c.conname<>'productUserAssignment_item_role_key'
    ORDER BY t.relname,c.conname
  LOOP
    EXECUTE 'ALTER TABLE '||replace(r.rel,'dflow.','dflow_prod.')||format(' ADD CONSTRAINT %I ',r.conname)||replace(r.def,'dflow.','dflow_prod.');
  END LOOP;

  FOR r IN
    SELECT pg_get_indexdef(i.indexrelid) AS def
    FROM pg_index i JOIN pg_class t ON t.oid=i.indrelid JOIN pg_namespace n ON n.oid=t.relnamespace
    LEFT JOIN pg_constraint c ON c.conindid=i.indexrelid
    JOIN pg_class x ON x.oid=i.indexrelid
    WHERE n.nspname='dflow' AND t.relname NOT LIKE 'sample%' AND c.oid IS NULL
      AND x.relname NOT IN ('idx_dflow_rfqitem_style_number_normalized','RFQVendor_item_vendor_summary_idx')
    ORDER BY t.relname,x.relname
  LOOP
    EXECUTE replace(r.def,' ON dflow.',' ON dflow_prod.');
  END LOOP;

  FOR r IN
    SELECT pg_get_functiondef(p.oid) AS def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='dflow' AND p.proname IN ('get_parent_id','get_child_id')
    ORDER BY p.proname
  LOOP
    EXECUTE replace(r.def,'dflow.','dflow_prod.');
  END LOOP;
END
$ddl$;

-- Exactly the seven legacy Sample tables present in Cloud SQL production.
CREATE TABLE dflow_prod.sample_box(LIKE plm.sample_box INCLUDING ALL);
CREATE TABLE dflow_prod.sample_factory_group(LIKE plm.sample_factory_group INCLUDING ALL);
CREATE TABLE dflow_prod.sample(LIKE plm.sample INCLUDING ALL);
CREATE TABLE dflow_prod.sample_event(LIKE plm.sample_event INCLUDING ALL);
CREATE TABLE dflow_prod.sample_comments(LIKE plm.sample_comments INCLUDING ALL);
CREATE TABLE dflow_prod.sample_attachment(LIKE plm.sample_attachment INCLUDING ALL);
CREATE TABLE dflow_prod.sample_shipment_item(LIKE plm.sample_shipment_item INCLUDING ALL);
ALTER TABLE dflow_prod.sample ADD CONSTRAINT sample_box_id_fk_fkey FOREIGN KEY(box_id_fk)REFERENCES dflow_prod.sample_box(box_id_pk)ON UPDATE CASCADE ON DELETE SET NULL,ADD CONSTRAINT sample_factory_group_id_fk_fkey FOREIGN KEY(factory_group_id_fk)REFERENCES dflow_prod.sample_factory_group(factory_group_id_pk)ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE dflow_prod.sample_attachment ADD CONSTRAINT sample_attachment_sample_id_fk_fkey FOREIGN KEY(sample_id_fk)REFERENCES dflow_prod.sample(sample_id_pk)ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE dflow_prod.sample_comments ADD CONSTRAINT sample_comments_sample_id_fk_fkey FOREIGN KEY(sample_id_fk)REFERENCES dflow_prod.sample(sample_id_pk)ON UPDATE CASCADE ON DELETE CASCADE,ADD CONSTRAINT sample_comments_user_id_fkey FOREIGN KEY(user_id)REFERENCES dflow_prod.users(id)ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE dflow_prod.sample_event ADD CONSTRAINT sample_event_sample_id_fk_fkey FOREIGN KEY(sample_id_fk)REFERENCES dflow_prod.sample(sample_id_pk)ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE dflow_prod.sample_shipment_item ADD CONSTRAINT sample_shipment_item_sample_id_fk_fkey FOREIGN KEY(sample_id_fk)REFERENCES dflow_prod.sample(sample_id_pk)ON UPDATE CASCADE ON DELETE CASCADE,ADD CONSTRAINT sample_shipment_item_box_id_fk_fkey FOREIGN KEY(box_id_fk)REFERENCES dflow_prod.sample_box(box_id_pk)ON UPDATE CASCADE ON DELETE SET NULL;

CREATE TABLE dflow_archive."AuditLog"(LIKE dflow_prod."AuditLog" INCLUDING STORAGE INCLUDING COMMENTS);
ALTER TABLE dflow_archive."AuditLog" ALTER COLUMN id DROP IDENTITY IF EXISTS;
ALTER TABLE dflow_archive."AuditLog" ADD CONSTRAINT "AuditLog_pkey" PRIMARY KEY(id);
COMMENT ON TABLE dflow_prod."AuditLog" IS 'Rolling live DesignFlow audit history: latest 24 months. Copy and tail high-water is id, never actionDate.';
COMMENT ON TABLE dflow_archive."AuditLog" IS 'Indefinite archive of AuditLog rows older than the live 24-month window; source IDs are preserved.';
CREATE INDEX "AuditLog_record_date_idx" ON dflow_prod."AuditLog"("moduleName",ref_id_fk,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_user_date_idx" ON dflow_prod."AuditLog"(user_id_fk,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_username_date_idx" ON dflow_prod."AuditLog"(username,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_action_date_idx" ON dflow_prod."AuditLog"("actionType","actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_date_idx" ON dflow_prod."AuditLog"("actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_record_date_idx" ON dflow_archive."AuditLog"("moduleName",ref_id_fk,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_user_date_idx" ON dflow_archive."AuditLog"(user_id_fk,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_username_date_idx" ON dflow_archive."AuditLog"(username,"actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_action_date_idx" ON dflow_archive."AuditLog"("actionType","actionDate" DESC,id DESC);
CREATE INDEX "AuditLog_date_idx" ON dflow_archive."AuditLog"("actionDate" DESC,id DESC);
CREATE VIEW dflow_prod."AuditLogHistory" WITH(security_invoker=true)AS SELECT a.*,false archived FROM dflow_prod."AuditLog"a UNION ALL SELECT a.*,true archived FROM dflow_archive."AuditLog"a;
COMMENT ON VIEW dflow_prod."AuditLogHistory" IS 'Search/export all audit history by business record, user, action, date range, and id.';

CREATE INDEX idx_dflow_prod_rfqitem_style_number_normalized ON dflow_prod."RFQItem"((upper(trim("rfqItem_style_number"))))WHERE "rfqItem_rfq_group"IS NOT NULL AND nullif(trim("rfqItem_style_number"),'')IS NOT NULL;
create or replace view public.style_tracker_rows_with_bridge as
select
  r.id,
  r.source_workbook_id,
  r.source_sheet,
  r.source_row_number,
  r.tracker_type,
  r.sku,
  r.group_id,
  r.description,
  r.customer,
  r.designer,
  r.commissioned,
  r.upc,
  r.customer_sku,
  r.licensor,
  r.license_status,
  r.royalty,
  r.concept_status,
  r.pre_production_status,
  r.production_status,
  r.default_vendor,
  r.discontinued,
  r.notes,
  r.row_data,
  r.imported_at,
  r.created_at,
  r.updated_at,
  r.updated_by,
  b.id as bridge_id,
  b.erp_item_id,
  b.style_group_id,
  b.company_id,
  b.public_licensor_id,
  b.core_licensor_id,
  b.factory_id,
  b.plm_item_id,
  b.match_status,
  b.match_confidence,
  b.match_notes,
  b.last_matched_at,
  erp.item_description as canonical_description,
  coalesce(selected_customer.display_name, selected_customer.name, bridge_customer.display_name, bridge_customer.name) as canonical_customer_name,
  coalesce(core_lic.name, public_lic.name) as canonical_licensor_name,
  factory.name as canonical_factory_name,
  sg.sku as style_group_sku,
  erp.style_number as erp_style_number,
  b.creative_designer_id,
  creative.name as canonical_designer_name,
  r.customer_id,
  coalesce(rfq.rfq_groups, '[]'::jsonb) as rfq_groups
from public.style_tracker_rows r
left join plm.style_tracker_item_bridge b on b.style_tracker_row_id = r.id
left join api.plm_item_list erp on erp.id = b.erp_item_id
left join public.style_groups sg on sg.id = b.style_group_id
left join core.customer bridge_customer on bridge_customer.id = b.company_id
left join core.customer selected_customer on selected_customer.id = r.customer_id
left join public.licensors public_lic on public_lic.id = b.public_licensor_id
left join core.licensor core_lic on core_lic.id = b.core_licensor_id
left join core.creative_designer creative on creative.id = b.creative_designer_id
left join core.factory factory on factory.id = b.factory_id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'id', per_group.id,
      'name', per_group.name,
      'linked_at', to_char(
        timezone('UTC', per_group.linked_at),
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      )
    )
    order by per_group.linked_at desc nulls last, per_group.id desc
  ) as rfq_groups
  from (
    select
      g."RFQGroup_id" as id,
      coalesce(
        nullif(trim(g."RFQGroup_name"), ''),
        'RFQ Group #' || g."RFQGroup_id"::text
      ) as name,
      max(coalesce(
        i."rfqItem_date_modified"::timestamptz,
        i."rfqItem_created_date",
        g.data_added::timestamptz
      )) as linked_at
    from dflow_prod."RFQItem" i
    join dflow_prod."RFQGroup" g
      on g."RFQGroup_id" = i."rfqItem_rfq_group"
    where upper(trim(i."rfqItem_style_number")) = upper(trim(r.row_data ->> 'rfq_code'))
      and nullif(trim(r.row_data ->> 'rfq_code'), '') is not null
      and i."rfqItem_rfq_group" is not null
    group by g."RFQGroup_id", g."RFQGroup_name"
  ) per_group
) rfq on true;

grant select on public.style_tracker_rows_with_bridge to authenticated, service_role;
revoke all on table public.style_tracker_rows_with_bridge from anon;

GRANT SELECT ON public.style_tracker_rows_with_bridge TO authenticated,service_role;
REVOKE ALL ON TABLE public.style_tracker_rows_with_bridge FROM anon;
REVOKE ALL ON TABLE public.style_tracker_rows_with_bridge FROM public;

DO $contract$
DECLARE n integer;
BEGIN
 SELECT count(*)INTO n FROM information_schema.tables WHERE table_schema='dflow_prod'AND table_type='BASE TABLE';
 IF n<>103 THEN RAISE EXCEPTION 'dflow_prod expected 103 tables, found %',n;END IF;
 IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='dflow_prod'AND table_name IN('sample_import_job','sample_import_row','sample_movement','sample_shipment_line','sample_stop_closeout','sample_visit','sample_visit_event','sample_visit_plan'))THEN RAISE EXCEPTION 'new Sample Tracking surface leaked';END IF;
 IF(SELECT count(*)FROM dflow_prod."AuditLog")<>0 OR(SELECT count(*)FROM dflow_archive."AuditLog")<>0 THEN RAISE EXCEPTION 'structure-only migration populated AuditLog';END IF;
END
$contract$;
