-- Additive: create DesignFlow table in shared schema core.
-- Mapped from DesignFlow `externalVendor` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.1.
-- Purpose: ERP vendor export / source-shaped staging
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS core."externalVendor" (
    id integer NOT NULL,
    "companyCode" character varying,
    "vendorCode" character varying NOT NULL,
    "vendorDesc" character varying,
    address1 character varying,
    address2 character varying,
    city character varying,
    state character varying,
    "zipCode" character varying,
    "phoneNo" character varying,
    "faxNo" character varying,
    email character varying,
    udf01 character varying,
    udf02 character varying,
    udf03 character varying,
    udf04 character varying,
    "udfDate01" character varying,
    "udfDate02" character varying,
    "countryCode" character varying,
    active character varying,
    address3 character varying,
    "payTermCode" character varying,
    "glCode" character varying,
    "separateCheck" character varying,
    "femaExpDate" character varying,
    "nbcExpDate" character varying,
    "modUser" character varying,
    "modTime" character varying,
    "createdUser" character varying,
    "createdTime" character varying
);

DO $$ BEGIN
  ALTER TABLE ONLY core."externalVendor"
    ADD CONSTRAINT "externalVendor_pkey" PRIMARY KEY ("vendorCode");
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE core."externalVendor" IS 'ERP vendor export / source-shaped staging';
