-- Transactional contracts for issue #1607 / Flow 4 remote requests.
BEGIN;

DO $$
DECLARE
  v_warehouse_sample integer;
  v_ningbo_sample integer;
  v_workflow_warehouse bigint;
  v_workflow_ningbo bigint;
  v_request uuid;
  v_warehouse_item uuid;
  v_ningbo_item uuid;
  v_reservation uuid;
  v_box integer;
  v_shipment bigint;
  v_before_movement bigint;
  v_first_line bigint;
  v_event_id bigint;
  v_event_replay_id bigint;
  v_event_definition text;
  v_reserve_definition text;
BEGIN
  IF to_regclass('dflow.sample_remote_request') IS NULL
     OR to_regclass('dflow.sample_remote_request_item') IS NULL
     OR to_regclass('dflow.sample_remote_request_history') IS NULL
     OR to_regclass('dflow.sample_reservation') IS NULL THEN
    RAISE EXCEPTION 'Flow 4 remote request relations are missing';
  END IF;

  INSERT INTO dflow.sample(origin,direction,sample_name,status,quantity_migration_state)
  VALUES('china_warehouse','inbound','flow4-warehouse-contract','created','known')
  RETURNING sample_id_pk INTO v_warehouse_sample;
  INSERT INTO dflow.sample_workflow(sample_id_fk,workflow_type,business_path,created_by_user)
  VALUES(v_warehouse_sample,'nyo_remote_china_inventory_request','china_warehouse_ningbo_nyo','contract-test')
  RETURNING sample_workflow_id INTO v_workflow_warehouse;

  INSERT INTO dflow.sample(origin,direction,sample_name,status,quantity_migration_state)
  VALUES('ningbo_inventory','inbound','flow4-ningbo-contract','created','known')
  RETURNING sample_id_pk INTO v_ningbo_sample;
  INSERT INTO dflow.sample_workflow(sample_id_fk,workflow_type,business_path,created_by_user)
  VALUES(v_ningbo_sample,'nyo_remote_china_inventory_request','ningbo_nyo','contract-test')
  RETURNING sample_workflow_id INTO v_workflow_ningbo;

  SELECT count(*) INTO v_before_movement FROM dflow.sample_movement
  WHERE sample_id_fk IN (v_warehouse_sample,v_ningbo_sample);

  INSERT INTO dflow.sample_remote_request(request_source,business_path,destination_type,destination_id,requested_by_user,requested_by_role,idempotency_key,request_hash)
  VALUES('mixed','mixed','office','nyo','nyo-user','nyo','request-1','request-hash-1')
  RETURNING sample_remote_request_id INTO v_request;

  INSERT INTO dflow.sample_remote_request_item(sample_remote_request_id,workflow_id,sample_id_fk,source_type,business_path,source_reference,idempotency_key,request_hash,created_by_user,created_by_role)
  VALUES(v_request,v_workflow_warehouse,v_warehouse_sample,'china_warehouse','china_warehouse_ningbo_nyo','warehouse-listing','item-warehouse','item-hash-warehouse','nyo-user','nyo')
  RETURNING sample_remote_request_item_id INTO v_warehouse_item;
  INSERT INTO dflow.sample_remote_request_item(sample_remote_request_id,workflow_id,sample_id_fk,source_type,business_path,source_reference,idempotency_key,request_hash,created_by_user,created_by_role)
  VALUES(v_request,v_workflow_ningbo,v_ningbo_sample,'ningbo_inventory','ningbo_nyo','ningbo-listing','item-ningbo','item-hash-ningbo','nyo-user','nyo')
  RETURNING sample_remote_request_item_id INTO v_ningbo_item;

  PERFORM dflow.post_sample_remote_request_event(v_warehouse_item,'requested','nyo-user','nyo','item-warehouse','item-hash-warehouse');
  PERFORM dflow.post_sample_remote_request_event(v_ningbo_item,'requested','nyo-user','nyo','item-ningbo','item-hash-ningbo');
  IF (SELECT count(*) FROM dflow.sample_remote_request_history WHERE sample_remote_request_item_id IN (v_warehouse_item,v_ningbo_item) AND to_state='requested') <> 2 THEN RAISE EXCEPTION 'initial requested history is missing'; END IF;

  SELECT sample_remote_request_history_id INTO v_event_id
  FROM dflow.post_sample_remote_request_event(v_warehouse_item,'awaiting_qc','nyo-user','nyo','warehouse-await','h-await');
  SELECT sample_remote_request_history_id INTO v_event_replay_id
  FROM dflow.post_sample_remote_request_event(v_warehouse_item,'awaiting_qc','nyo-user','nyo','warehouse-await','h-await');
  IF v_event_replay_id <> v_event_id THEN RAISE EXCEPTION 'event replay did not return the committed event'; END IF;
  BEGIN
    PERFORM dflow.post_sample_remote_request_event(v_warehouse_item,'confirmed','wrong-user','ningbo','warehouse-wrong-role','h-wrong');
    RAISE EXCEPTION 'wrong role confirmed warehouse stock';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM dflow.post_sample_remote_request_event(v_warehouse_item,'confirmed','qc-user','qc','warehouse-confirm','h-confirm');
  PERFORM dflow.post_sample_remote_request_event(v_warehouse_item,'in_transit_to_ningbo','qc-user','qc','warehouse-transit','h-transit');
  PERFORM dflow.post_sample_remote_request_event(v_warehouse_item,'received','ningbo-user','ningbo','warehouse-received','h-received');

  SELECT sample_reservation_id INTO v_reservation
  FROM dflow.reserve_sample_remote_request_item(v_warehouse_item,'ningbo-user','ningbo','warehouse-reserve','h-reserve');
  IF (SELECT sample_reservation_id FROM dflow.reserve_sample_remote_request_item(v_warehouse_item,'ningbo-user','ningbo','warehouse-reserve','h-reserve')) <> v_reservation THEN
    RAISE EXCEPTION 'reservation replay duplicated the reservation';
  END IF;
  BEGIN
    PERFORM dflow.reserve_sample_remote_request_item(v_warehouse_item,'ningbo-user','ningbo','warehouse-reserve-2','h-reserve-2');
    RAISE EXCEPTION 'a duplicate open reservation was accepted';
  EXCEPTION WHEN check_violation OR unique_violation THEN NULL;
  END;

  INSERT INTO dflow.sample_box(box_label,status,origin_office,dest_office)
  VALUES('flow4-contract-box','open','ningbo','nyo') RETURNING box_id_pk INTO v_box;
  INSERT INTO dflow.sample_shipment(origin_location_type,origin_location_id,destination_location_type,destination_location_id,state,actor_user,actor_role,idempotency_key,request_hash)
  VALUES('office','ningbo','office','nyo','packed','ningbo-user','ningbo','flow4-shipment','flow4-shipment-hash')
  RETURNING sample_shipment_id INTO v_shipment;

  PERFORM dflow.pack_sample_reservation(v_reservation,v_box,v_shipment,'ningbo','office','nyo','ningbo_to_nyc','ningbo-user','ningbo','warehouse-pack','h-pack');
  SELECT packed_shipment_line_id INTO v_first_line FROM dflow.sample_reservation WHERE sample_reservation_id=v_reservation;
  PERFORM dflow.pack_sample_reservation(v_reservation,v_box,v_shipment,'ningbo','office','nyo','ningbo_to_nyc','ningbo-user','ningbo','warehouse-pack','h-pack');
  IF (SELECT count(*) FROM dflow.sample_shipment_item WHERE sample_id_fk=v_warehouse_sample AND box_id_fk=v_box) <> 1
     OR (SELECT count(*) FROM dflow.sample_shipment_line WHERE sample_id_fk=v_warehouse_sample AND idempotency_key='warehouse-pack') <> 1
     OR (SELECT packed_shipment_line_id FROM dflow.sample_reservation WHERE sample_reservation_id=v_reservation) <> v_first_line THEN
    RAISE EXCEPTION 'packing replay duplicated membership or shipment intent';
  END IF;
  BEGIN
    PERFORM dflow.pack_sample_reservation(v_reservation,v_box,v_shipment,'ningbo','office','nyo','ningbo_to_nyc','ningbo-user','ningbo','competing-pack','h-pack');
    RAISE EXCEPTION 'a competing pack command consumed an already packed reservation';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF pg_get_functiondef('dflow.pack_sample_reservation(uuid,integer,bigint,text,text,text,text,text,text,text,text)'::regprocedure) NOT LIKE '%FOR UPDATE%' THEN
    RAISE EXCEPTION 'packing does not serialize on a row lock';
  END IF;

  v_event_definition := lower(pg_get_functiondef('dflow.post_sample_remote_request_event(uuid,text,text,text,text,text,text,jsonb)'::regprocedure));
  IF strpos(v_event_definition,'for update') = 0
     OR strpos(v_event_definition,'from dflow.sample_remote_request_history') = 0
     OR strpos(v_event_definition,'for update') > strpos(v_event_definition,'from dflow.sample_remote_request_history') THEN
    RAISE EXCEPTION 'event idempotency lookup occurs before the item row lock';
  END IF;
  v_reserve_definition := lower(pg_get_functiondef('dflow.reserve_sample_remote_request_item(uuid,text,text,text,text)'::regprocedure));
  IF strpos(v_reserve_definition,'for update') = 0
     OR strpos(v_reserve_definition,'from dflow.sample_reservation') = 0
     OR strpos(v_reserve_definition,'for update') > strpos(v_reserve_definition,'from dflow.sample_reservation') THEN
    RAISE EXCEPTION 'reservation idempotency lookup occurs before the item row lock';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='dflow.sample_reservation'::regclass
      AND pg_get_constraintdef(oid) LIKE '%released%'
  ) THEN RAISE EXCEPTION 'reservation advertises an unreachable released lifecycle'; END IF;

  PERFORM dflow.post_sample_remote_request_event(v_ningbo_item,'awaiting_ningbo','nyo-user','nyo','ningbo-await','n-await');
  PERFORM dflow.post_sample_remote_request_event(v_ningbo_item,'not_found','ningbo-user','ningbo','ningbo-not-found','n-not-found','physically absent');
  BEGIN
    PERFORM dflow.reserve_sample_remote_request_item(v_ningbo_item,'ningbo-user','ningbo','ningbo-reserve','n-reserve');
    RAISE EXCEPTION 'not-found stock was reserved';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  IF has_table_privilege('service_role','dflow.sample_remote_request_history','UPDATE')
     OR has_table_privilege('service_role','dflow.sample_remote_request_history','DELETE') THEN
    RAISE EXCEPTION 'service_role can mutate append-only request history';
  END IF;

  IF (SELECT count(*) FROM dflow.sample_movement WHERE sample_id_fk IN (v_warehouse_sample,v_ningbo_sample)) <> v_before_movement THEN
    RAISE EXCEPTION 'request, confirmation, reservation, or packing changed physical custody';
  END IF;
END $$;

ROLLBACK;

-- The sequential assertions above prove ordinary replay. These two dblink
-- drills prove the harder overlapping-retry window: another backend owns the
-- item lock, commits the same operation, and the blocked API call must wake up
-- and return that committed row rather than attempt a duplicate transition.
-- The contract runner is an owner of its throwaway database, so install the
-- test-only connection helper here; absence of the extension must fail loudly.
CREATE EXTENSION IF NOT EXISTS dblink;
DROP ROLE IF EXISTS flow4_concurrency_writer;
CREATE ROLE flow4_concurrency_writer LOGIN PASSWORD 'flow4-throwaway-concurrency-only';
GRANT USAGE ON SCHEMA dflow TO flow4_concurrency_writer;
GRANT SELECT,UPDATE ON dflow.sample_remote_request_item TO flow4_concurrency_writer;
GRANT SELECT,INSERT ON dflow.sample_remote_request_history,dflow.sample_reservation TO flow4_concurrency_writer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA dflow TO flow4_concurrency_writer;

BEGIN;

DO $$
DECLARE
  v_event_sample integer;
  v_reserve_sample integer;
  v_event_workflow bigint;
  v_reserve_workflow bigint;
BEGIN
  INSERT INTO dflow.sample(origin,direction,sample_name,status,quantity_migration_state)
  VALUES('china_warehouse','inbound','flow4-event-concurrency-contract','created','known')
  RETURNING sample_id_pk INTO v_event_sample;
  INSERT INTO dflow.sample_workflow(sample_id_fk,workflow_type,business_path,created_by_user)
  VALUES(v_event_sample,'nyo_remote_china_inventory_request','china_warehouse_ningbo_nyo','contract-test')
  RETURNING sample_workflow_id INTO v_event_workflow;

  INSERT INTO dflow.sample(origin,direction,sample_name,status,quantity_migration_state)
  VALUES('china_warehouse','inbound','flow4-reserve-concurrency-contract','created','known')
  RETURNING sample_id_pk INTO v_reserve_sample;
  INSERT INTO dflow.sample_workflow(sample_id_fk,workflow_type,business_path,created_by_user)
  VALUES(v_reserve_sample,'nyo_remote_china_inventory_request','china_warehouse_ningbo_nyo','contract-test')
  RETURNING sample_workflow_id INTO v_reserve_workflow;

  INSERT INTO dflow.sample_remote_request(
    sample_remote_request_id,request_source,business_path,destination_type,destination_id,
    requested_by_user,requested_by_role,idempotency_key,request_hash
  ) VALUES(
    '16070000-0000-4000-8000-000000000000','mixed','mixed','office','nyo',
    'nyo-user','nyo','flow4-concurrency-request','flow4-concurrency-request-hash'
  );

  INSERT INTO dflow.sample_remote_request_item(
    sample_remote_request_item_id,sample_remote_request_id,workflow_id,sample_id_fk,
    source_type,business_path,source_reference,current_state,idempotency_key,request_hash,
    created_by_user,created_by_role
  ) VALUES
    ('16070000-0000-4000-8000-000000000001','16070000-0000-4000-8000-000000000000',v_event_workflow,v_event_sample,
     'china_warehouse','china_warehouse_ningbo_nyo','event-concurrency','requested','event-concurrency-item','event-concurrency-item-hash','nyo-user','nyo'),
    ('16070000-0000-4000-8000-000000000002','16070000-0000-4000-8000-000000000000',v_reserve_workflow,v_reserve_sample,
     'china_warehouse','china_warehouse_ningbo_nyo','reserve-concurrency','received','reserve-concurrency-item','reserve-concurrency-item-hash','nyo-user','nyo');
END $$;

COMMIT;

DO $event_concurrency$
DECLARE
  v_has_dblink boolean;
  v_ready boolean := false;
  v_attempt integer;
  v_returned_id bigint;
  v_committed_id bigint;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname='dblink') INTO v_has_dblink;
  IF NOT v_has_dblink THEN
    RAISE EXCEPTION 'FLOW4 EVENT CONCURRENCY REQUIRED: dblink is not installed, so the genuine two-session overlapping retry was not proved';
  END IF;

  BEGIN
    -- A purpose-built login confines the remote writer to exactly the relations
    -- exercised below. It exists only in this throwaway contract database.
    PERFORM dblink_connect('flow4_event_writer',format(
      'host=127.0.0.1 port=%s dbname=%s user=flow4_concurrency_writer password=flow4-throwaway-concurrency-only',
      inet_server_port(),current_database()
    ));
  EXCEPTION WHEN connection_exception THEN
    RAISE EXCEPTION 'FLOW4 EVENT CONCURRENCY REQUIRED: dblink cannot open the required second database session (%)', SQLERRM;
  END;

  BEGIN
    PERFORM dblink_send_query('flow4_event_writer', $remote$
      DO $writer$
      BEGIN
        PERFORM 1 FROM dflow.sample_remote_request_item
         WHERE sample_remote_request_item_id='16070000-0000-4000-8000-000000000001' FOR UPDATE;
        PERFORM pg_advisory_lock(16070001);
        PERFORM pg_sleep(0.75);
        UPDATE dflow.sample_remote_request_item
           SET current_state='awaiting_qc',updated_at=now()
         WHERE sample_remote_request_item_id='16070000-0000-4000-8000-000000000001';
        INSERT INTO dflow.sample_remote_request_history(
          sample_remote_request_item_id,from_state,to_state,actor_user,actor_role,
          idempotency_key,request_hash
        ) VALUES(
          '16070000-0000-4000-8000-000000000001','requested','awaiting_qc','nyo-user','nyo',
          'event-overlap','event-overlap-hash'
        );
        PERFORM pg_advisory_unlock(16070001);
      END $writer$;
    $remote$);

    FOR v_attempt IN 1..100 LOOP
      IF NOT pg_try_advisory_lock(16070001) THEN v_ready := true; EXIT; END IF;
      PERFORM pg_advisory_unlock(16070001);
      PERFORM pg_sleep(0.02);
    END LOOP;
    IF NOT v_ready THEN RAISE EXCEPTION 'event concurrency writer never acquired its item lock'; END IF;

    SELECT sample_remote_request_history_id INTO v_returned_id
      FROM dflow.post_sample_remote_request_event(
        '16070000-0000-4000-8000-000000000001','awaiting_qc','nyo-user','nyo',
        'event-overlap','event-overlap-hash'
      );
    PERFORM status FROM dblink_get_result('flow4_event_writer') AS result(status text);
    SELECT sample_remote_request_history_id INTO v_committed_id
      FROM dflow.sample_remote_request_history
     WHERE sample_remote_request_item_id='16070000-0000-4000-8000-000000000001'
       AND idempotency_key='event-overlap';
    IF v_returned_id IS DISTINCT FROM v_committed_id THEN
      RAISE EXCEPTION 'blocked event replay returned %, not committed history %',v_returned_id,v_committed_id;
    END IF;
    PERFORM dblink_disconnect('flow4_event_writer');
    RAISE NOTICE 'FLOW4 EVENT CONCURRENCY PASS: blocked replay returned committed history %',v_committed_id;
  EXCEPTION WHEN OTHERS THEN
    BEGIN PERFORM dblink_disconnect('flow4_event_writer'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
  END;
END $event_concurrency$;

DO $reserve_concurrency$
DECLARE
  v_has_dblink boolean;
  v_ready boolean := false;
  v_attempt integer;
  v_returned_id uuid;
  v_committed_id uuid;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname='dblink') INTO v_has_dblink;
  IF NOT v_has_dblink THEN
    RAISE EXCEPTION 'FLOW4 RESERVATION CONCURRENCY REQUIRED: dblink is not installed, so the genuine two-session overlapping retry was not proved';
  END IF;

  BEGIN
    PERFORM dblink_connect('flow4_reserve_writer',format(
      'host=127.0.0.1 port=%s dbname=%s user=flow4_concurrency_writer password=flow4-throwaway-concurrency-only',
      inet_server_port(),current_database()
    ));
  EXCEPTION WHEN connection_exception THEN
    RAISE EXCEPTION 'FLOW4 RESERVATION CONCURRENCY REQUIRED: dblink cannot open the required second database session (%)', SQLERRM;
  END;

  BEGIN
    PERFORM dblink_send_query('flow4_reserve_writer', $remote$
      DO $writer$
      DECLARE v_sample_id integer;
      BEGIN
        SELECT sample_id_fk INTO v_sample_id FROM dflow.sample_remote_request_item
         WHERE sample_remote_request_item_id='16070000-0000-4000-8000-000000000002' FOR UPDATE;
        PERFORM pg_advisory_lock(16070002);
        PERFORM pg_sleep(0.75);
        INSERT INTO dflow.sample_reservation(
          sample_reservation_id,sample_remote_request_item_id,sample_id_fk,reserved_by_user,
          idempotency_key,request_hash
        ) VALUES(
          '16070000-0000-4000-8000-000000000003','16070000-0000-4000-8000-000000000002',v_sample_id,
          'ningbo-user','reserve-overlap','reserve-overlap-hash'
        );
        UPDATE dflow.sample_remote_request_item
           SET current_state='reserved_for_next_box',updated_at=now()
         WHERE sample_remote_request_item_id='16070000-0000-4000-8000-000000000002';
        INSERT INTO dflow.sample_remote_request_history(
          sample_remote_request_item_id,from_state,to_state,actor_user,actor_role,
          idempotency_key,request_hash
        ) VALUES(
          '16070000-0000-4000-8000-000000000002','received','reserved_for_next_box','ningbo-user','ningbo',
          'reserve-overlap','reserve-overlap-hash'
        );
        PERFORM pg_advisory_unlock(16070002);
      END $writer$;
    $remote$);

    FOR v_attempt IN 1..100 LOOP
      IF NOT pg_try_advisory_lock(16070002) THEN v_ready := true; EXIT; END IF;
      PERFORM pg_advisory_unlock(16070002);
      PERFORM pg_sleep(0.02);
    END LOOP;
    IF NOT v_ready THEN RAISE EXCEPTION 'reservation concurrency writer never acquired its item lock'; END IF;

    SELECT sample_reservation_id INTO v_returned_id
      FROM dflow.reserve_sample_remote_request_item(
        '16070000-0000-4000-8000-000000000002','ningbo-user','ningbo','reserve-overlap','reserve-overlap-hash'
      );
    PERFORM status FROM dblink_get_result('flow4_reserve_writer') AS result(status text);
    SELECT sample_reservation_id INTO v_committed_id
      FROM dflow.sample_reservation WHERE idempotency_key='reserve-overlap';
    IF v_returned_id IS DISTINCT FROM v_committed_id THEN
      RAISE EXCEPTION 'blocked reservation replay returned %, not committed reservation %',v_returned_id,v_committed_id;
    END IF;
    PERFORM dblink_disconnect('flow4_reserve_writer');
    RAISE NOTICE 'FLOW4 RESERVATION CONCURRENCY PASS: blocked replay returned committed reservation %',v_committed_id;
  EXCEPTION WHEN OTHERS THEN
    BEGIN PERFORM dblink_disconnect('flow4_reserve_writer'); EXCEPTION WHEN OTHERS THEN NULL; END;
    RAISE;
  END;
END $reserve_concurrency$;

BEGIN;
DELETE FROM dflow.sample_remote_request_history
 WHERE sample_remote_request_item_id IN ('16070000-0000-4000-8000-000000000001','16070000-0000-4000-8000-000000000002');
DELETE FROM dflow.sample_reservation WHERE sample_reservation_id='16070000-0000-4000-8000-000000000003';
DELETE FROM dflow.sample_remote_request_item WHERE sample_remote_request_id='16070000-0000-4000-8000-000000000000';
DELETE FROM dflow.sample_remote_request WHERE sample_remote_request_id='16070000-0000-4000-8000-000000000000';
DELETE FROM dflow.sample_workflow WHERE created_by_user='contract-test' AND sample_id_fk IN (
  SELECT sample_id_pk FROM dflow.sample WHERE sample_name IN ('flow4-event-concurrency-contract','flow4-reserve-concurrency-contract')
);
DELETE FROM dflow.sample WHERE sample_name IN ('flow4-event-concurrency-contract','flow4-reserve-concurrency-contract');
COMMIT;
DROP ROLE flow4_concurrency_writer;
