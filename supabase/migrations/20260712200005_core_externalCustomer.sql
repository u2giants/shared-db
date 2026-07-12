-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `externalCustomer` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: ERP-shaped customer rows; lineage via company_source_ref
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."externalCustomer" (
    id integer NOT NULL,
    "companyCode" character varying,
    "customerCode" character varying NOT NULL,
    active character varying,
    address1 character varying,
    address2 character varying,
    "aRCustomerCode" character varying,
    city character varying,
    "countryCode" character varying,
    "customerDesc" character varying,
    "customerTypeCode" character varying,
    "faxNo" character varying,
    "phoneNo" character varying,
    state character varying,
    "useConsolidatedInvoice" character varying,
    "zipCode" character varying,
    "parentCustomerCode" character varying,
    "customerDBA" character varying,
    udf01 character varying,
    udf02 character varying,
    udf03 character varying,
    udf04 character varying,
    "udfDate01" character varying,
    "udfDate02" character varying,
    "oldCustomerCode" character varying,
    "vendorNumber" character varying,
    address3 character varying,
    "regionCode" character varying,
    "dsCat" character varying,
    "salesPersonCode1" character varying,
    "salesPersonCode2" character varying,
    "commissionPerc1" character varying,
    "commissionPerc2" character varying,
    "factorCode" character varying,
    "currencyCode" character varying,
    "glCode" character varying,
    "createdTime" character varying,
    "createdUser" character varying,
    "modTime" character varying,
    "modUser" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY core."externalCustomer"
    ADD CONSTRAINT "externalCustomer_pkey" PRIMARY KEY ("customerCode");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."externalCustomer" IS 'ERP-shaped customer rows; lineage via company_source_ref';
