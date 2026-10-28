-- HU-COM-005 (-db) DP-D5-7 (default, PROPOSED 2026-10-28): the emergency and risk data of a customer
-- lives apart from the ordinary row, so that "restricted access" is a grant and not a promise of the
-- code. The reader loses SELECT in dcl-grants-005. The content is a versioned JSON envelope written
-- encrypted by the application (DP-D5-1); the database never holds the key. Where the consent evidence
-- lives is open (DP-D5-7, DP-D5-10), so no consent column exists. No DEFAULT; no DELETE (AC-D5.9).
CREATE TABLE commercial_reservation.customer_sensitive_data (
    customer_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_customer_sensitive_data_tenant_required NOT NULL,
    emergency_info jsonb CONSTRAINT chk_customer_sensitive_data_emergency_info_required NOT NULL,
    CONSTRAINT pk_customer_sensitive_data PRIMARY KEY (customer_id),
    CONSTRAINT fk_customer_sensitive_data_customer FOREIGN KEY (customer_id)
        REFERENCES commercial_reservation.customer (customer_id) ON DELETE RESTRICT
);
