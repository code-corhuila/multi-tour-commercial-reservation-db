-- HU-COM-013 (-db) DP-02a (PROPOSED, docs pull request 1002): the cancellation penalty a tenant, or one of its services, applies when the customer cancels
-- (PDR RF-021, RN-RES-008). service_id empty = the tenant level. The penalty is a share of the validated values in basis points, 0 (none) to 10 000 (all).
-- The author, the reason (never blank) and the time of the LAST change stay on the row. Nothing has a DEFAULT and no row is seeded: a tenant without a row
-- has no penalty. Which row wins, the service one or the tenant one, is the application's, as for payment_condition; the two partial uniques are in 10_indexes/059.
CREATE TABLE commercial_reservation.cancellation_penalty_policy (
    cancellation_penalty_policy_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_cancellation_penalty_policy_tenant_required NOT NULL,
    service_id uuid,
    penalty_bp integer CONSTRAINT chk_cancellation_penalty_policy_penalty_required NOT NULL,
    changed_by uuid CONSTRAINT chk_cancellation_penalty_policy_changed_by_required NOT NULL,
    change_reason text CONSTRAINT chk_cancellation_penalty_policy_change_reason_required NOT NULL,
    changed_at timestamptz CONSTRAINT chk_cancellation_penalty_policy_changed_at_required NOT NULL,
    CONSTRAINT pk_cancellation_penalty_policy PRIMARY KEY (cancellation_penalty_policy_id),
    CONSTRAINT fk_cancellation_penalty_policy_service FOREIGN KEY (service_id)
        REFERENCES commercial_reservation.catalog_service (service_id) ON DELETE RESTRICT,
    CONSTRAINT chk_cancellation_penalty_policy_penalty CHECK (penalty_bp BETWEEN 0 AND 10000),
    CONSTRAINT chk_cancellation_penalty_policy_change_reason CHECK (btrim(change_reason) <> '')
);
