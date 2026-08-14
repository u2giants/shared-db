-- Transactional Release A contract proof. Run after all migrations.
BEGIN;

DO $$
DECLARE
  v_sample integer;
  v_box integer;
  v_batch bigint;
  v_workflow bigint;
  v_carrier smallint;
  v_shipment bigint;
BEGIN
  IF (SELECT count(*) FROM dflow.sample_carrier WHERE is_active) <> 4 THEN
    RAISE EXCEPTION 'Release A must seed exactly four proven active carriers';
  END IF;

  INSERT INTO dflow.sample(origin,direction,sample_name,status,quantity_migration_state)
  VALUES('usa_bought','outbound','release-a-contract','created','known')
  RETURNING sample_id_pk INTO v_sample;

  INSERT INTO dflow.sample_creation_batch(mode,entry_method,idempotency_key,request_hash,created_by_user,created_by_role)
  VALUES('single','manual','release-a-batch','hash-a','contract-test','production')
  RETURNING creation_batch_id INTO v_batch;

  INSERT INTO dflow.sample_workflow(sample_id_fk,creation_batch_id,workflow_type,business_path,created_by_user)
  VALUES(v_sample,v_batch,'nyo_purchased_factory_reference','nyo_ningbo','contract-test')
  RETURNING sample_workflow_id INTO v_workflow;

  BEGIN
    INSERT INTO dflow.sample_workflow(sample_id_fk,workflow_type,business_path,created_by_user)
    VALUES(v_sample,'vendor_unsolicited_offer','nyo_factory','contract-test');
    RAISE EXCEPTION 'invalid workflow/path pair was accepted';
  EXCEPTION WHEN check_violation OR unique_violation THEN NULL;
  END;

  INSERT INTO dflow.sample_path_revision(sample_workflow_id,revision,business_path,reason,changed_by_user)
  VALUES(v_workflow,1,'nyo_ningbo','initial path','contract-test');
  BEGIN
    UPDATE dflow.sample_path_revision SET reason='rewritten' WHERE sample_workflow_id=v_workflow;
    RAISE EXCEPTION 'append-only path revision was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  INSERT INTO dflow.sample_box(box_label,direction,status,ownership_state,current_custody_type,current_custody_id)
  VALUES(' Release A Box ','outbound','packing','internal','office','nyc')
  RETURNING box_id_pk INTO v_box;
  BEGIN
    INSERT INTO dflow.sample_box(box_label,direction,status,ownership_state,current_custody_type,current_custody_id)
    VALUES('release a box','outbound','packing','internal','office','nyc');
    RAISE EXCEPTION 'normalized active box name collision was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  SELECT sample_carrier_id INTO v_carrier FROM dflow.sample_carrier WHERE carrier_code='ups';
  INSERT INTO dflow.sample_shipment(carrier_id,tracking_number,origin_location_type,origin_location_id,
    destination_location_type,destination_location_id,state,actor_user,actor_role,idempotency_key,request_hash)
  VALUES(v_carrier,'TRACK-RELEASE-A','warehouse','china_warehouse','office','ningbo','packed',
    'contract-test','production','release-a-shipment','hash-s')
  RETURNING sample_shipment_id INTO v_shipment;

  INSERT INTO dflow.sample_shipment_line(sample_id_fk,box_id_fk,quantity_intended,origin_location_type,
    origin_location_id,destination_location_type,destination_location_id,route_leg,state,idempotency_key,
    request_hash,created_by_user,created_by_role,sample_shipment_id)
  VALUES(v_sample,v_box,1,'warehouse','china_warehouse','office','ningbo','warehouse_to_ningbo','packed',
    'release-a-line','hash-l','contract-test','production',v_shipment);

  PERFORM dflow.post_sample_movement(v_sample,1,'terminal','created','warehouse','china_warehouse',
    'create','contract-test','production','release-a-create','hash-m');
  IF NOT EXISTS (
    SELECT 1 FROM dflow.sample_inventory
    WHERE sample_id_fk=v_sample AND product_location_type='warehouse'
      AND product_location_id='china_warehouse' AND quantity=1 AND is_eligible
  ) THEN
    RAISE EXCEPTION 'warehouse stock absent or ineligible in Release A inventory';
  END IF;

  BEGIN
    INSERT INTO dflow.sample_shipment(carrier_id,tracking_number,origin_location_type,origin_location_id,
      destination_location_type,destination_location_id,state,actor_user,actor_role,idempotency_key,request_hash)
    VALUES(v_carrier,'track-release-a','warehouse','china_warehouse','office','ningbo','packed',
      'contract-test','production','release-a-shipment-duplicate','hash-s2');
    RAISE EXCEPTION 'active carrier/tracking duplicate was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  IF (SELECT count(*) FROM dflow.sample_workflow WHERE sample_id_fk=v_sample) <> 1 THEN
    RAISE EXCEPTION 'workflow identity is not one-to-one with sample';
  END IF;
END $$;

ROLLBACK;
