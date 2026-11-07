-- HU-COM-017 (-db) plan D-03 (PROPOSED defaults): one row per application of a credit to a reservation (credit_balance_applications of the dictionary), appended and
-- never edited. The person who applied it and whether it was the customer or the staff are recorded (AC5 of the story). The application user inherits the writer,
-- so UPDATE is withdrawn in 03_dcl/01_grants/015 and DELETE was never granted. Amounts are bigint cents; no DEFAULT. The guard of holder, tenant and ceiling is slice 2.
CREATE TABLE commercial_reservation.credit_balance_application (
    credit_balance_application_id uuid NOT NULL,
    credit_balance_id uuid CONSTRAINT chk_credit_balance_application_credit_required NOT NULL,
    tenant_id uuid CONSTRAINT chk_credit_balance_application_tenant_required NOT NULL,
    target_reservation_id uuid CONSTRAINT chk_credit_balance_application_target_required NOT NULL,
    applied_amount_cents bigint CONSTRAINT chk_credit_balance_application_amount_required NOT NULL,
    applied_at timestamptz CONSTRAINT chk_credit_balance_application_applied_at_required NOT NULL,
    applied_by uuid CONSTRAINT chk_credit_balance_application_applied_by_required NOT NULL,
    applied_by_kind text CONSTRAINT chk_credit_balance_application_kind_required NOT NULL,
    CONSTRAINT pk_credit_balance_application PRIMARY KEY (credit_balance_application_id),
    CONSTRAINT fk_credit_balance_application_credit FOREIGN KEY (credit_balance_id)
        REFERENCES commercial_reservation.credit_balance (credit_balance_id) ON DELETE RESTRICT,
    CONSTRAINT fk_credit_balance_application_reservation FOREIGN KEY (target_reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_credit_balance_application_amount_positive CHECK (applied_amount_cents > 0),
    CONSTRAINT chk_credit_balance_application_kind CHECK (applied_by_kind IN ('CUSTOMER', 'STAFF'))
);
