-- HU-COM-009 (-db) plan D-11 (PROPOSED): the payment parameters of a tenant, or of one of its services (service_id empty = the tenant level). A row means
-- its payment type is enabled; a tenant with no row offers no type (DP-D9-13, no seed). Hours are 1 to 720 and the minimum deposit is 1 to 10 000 basis
-- points, required for a deposit and empty for a total payment (bounds of the portal amendment A.3, PROPOSED). The media columns are DP-D9-5 (PROPOSED).
-- The author, the reason (never blank) and the time of the LAST change stay on the row; the history is not kept here (DP-D9-10, debt DD-8).
-- No penalty column. Which row wins, the service one or the tenant one, is the application's (DP-D9-6); the two partial uniques are in 10_indexes/024.
CREATE TABLE commercial_reservation.payment_condition (
    payment_condition_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_payment_condition_tenant_required NOT NULL,
    service_id uuid,
    payment_type text CONSTRAINT chk_payment_condition_type_required NOT NULL,
    initial_wait_hours integer CONSTRAINT chk_payment_condition_initial_wait_required NOT NULL,
    additional_wait_hours integer CONSTRAINT chk_payment_condition_additional_wait_required NOT NULL,
    minimum_deposit_bp integer,
    balance_deadline_advance_hours integer,
    transfer_enabled boolean CONSTRAINT chk_payment_condition_transfer_enabled_required NOT NULL,
    cash_enabled boolean CONSTRAINT chk_payment_condition_cash_enabled_required NOT NULL,
    changed_by uuid CONSTRAINT chk_payment_condition_changed_by_required NOT NULL,
    change_reason text CONSTRAINT chk_payment_condition_change_reason_required NOT NULL,
    changed_at timestamptz CONSTRAINT chk_payment_condition_changed_at_required NOT NULL,
    CONSTRAINT pk_payment_condition PRIMARY KEY (payment_condition_id),
    CONSTRAINT fk_payment_condition_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_condition_type CHECK (payment_type IN ('FULL_PAYMENT', 'DEPOSIT')),
    CONSTRAINT chk_payment_condition_initial_wait CHECK (initial_wait_hours BETWEEN 1 AND 720),
    CONSTRAINT chk_payment_condition_additional_wait CHECK (additional_wait_hours BETWEEN 1 AND 720),
    CONSTRAINT chk_payment_condition_minimum_deposit CHECK (
        (payment_type = 'DEPOSIT' AND minimum_deposit_bp IS NOT NULL AND minimum_deposit_bp BETWEEN 1 AND 10000)
        OR (payment_type = 'FULL_PAYMENT' AND minimum_deposit_bp IS NULL)),
    CONSTRAINT chk_payment_condition_balance_advance CHECK (
        balance_deadline_advance_hours IS NULL OR balance_deadline_advance_hours BETWEEN 1 AND 720),
    CONSTRAINT chk_payment_condition_change_reason CHECK (btrim(change_reason) <> '')
);
