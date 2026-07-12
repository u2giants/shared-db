-- Additive: create DesignFlow table in shared schema plm.
-- Mapped from DesignFlow `ProdPaymentTerms` per
-- docs/designflow-master-data-migration/designflow-schema-segregation.md section 4.3.
-- Purpose: Payment terms reference
-- Branch: db-migration. Apply on preview first (shared-db-gatekeeper / AGENTS.md).
--
CREATE TABLE IF NOT EXISTS plm."ProdPaymentTerms" (
    id integer,
    "CompanyCode" character varying,
    "PayTermCode" character varying,
    "PayTermDesc" character varying,
    "PaymentTermType" character varying,
    "PaymentDueDays" character varying,
    "PaymentDiscDays" character varying,
    "PaymentCutOffDay" character varying,
    "PaymentFixedDueDay" character varying
);

COMMENT ON TABLE plm."ProdPaymentTerms" IS 'Payment terms reference';
