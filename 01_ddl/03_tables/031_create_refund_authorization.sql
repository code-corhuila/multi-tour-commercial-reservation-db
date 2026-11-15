-- HU-COM-016 (-db) plan D-03, DP-D16-1, DP-D16-2 (PROPOSED defaults): one row per authorized refund (refund_authorizations of the dictionary) plus the
-- execution state the saga of HU-WFL-003 marks on this side. EXECUTED carries the identifier of the cash movement, a logical reference with no key
-- (Annex J.3.4). The decision reference is present for the four decision origins and null for the two others. Amounts are bigint cents; no DEFAULT.
CREATE TABLE commercial_reservation.refund_authorization (
    refund_authorization_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_refund_authorization_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_refund_authorization_reservation_required NOT NULL,
    refund_origin text CONSTRAINT chk_refund_authorization_origin_required NOT NULL,
    financial_decision_id uuid,
    potential_refund_value_cents bigint CONSTRAINT chk_refund_authorization_potential_required NOT NULL,
    authorized_amount_cents bigint CONSTRAINT chk_refund_authorization_amount_required NOT NULL,
    reason text CONSTRAINT chk_refund_authorization_reason_required NOT NULL,
    authorization_mode text CONSTRAINT chk_refund_authorization_mode_required NOT NULL,
    authorized_by uuid,
    authorized_at timestamptz CONSTRAINT chk_refund_authorization_authorized_at_required NOT NULL,
    execution_due_at timestamptz CONSTRAINT chk_refund_authorization_due_at_required NOT NULL,
    execution_state text CONSTRAINT chk_refund_authorization_state_required NOT NULL,
    executing_at timestamptz,
    executed_by uuid,
    outflow_method text,
    executed_at timestamptz,
    cash_movement_id uuid,
    overdue_marked_at timestamptz,
    CONSTRAINT pk_refund_authorization PRIMARY KEY (refund_authorization_id),
    CONSTRAINT fk_refund_authorization_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_refund_authorization_decision FOREIGN KEY (financial_decision_id)
        REFERENCES commercial_reservation.financial_decision (financial_decision_id) ON DELETE RESTRICT,
    CONSTRAINT chk_refund_authorization_origin CHECK (refund_origin IN
        ('PENDING_TREATMENT', 'MODIFICATION_EXCESS', 'CUSTOMER_CANCELLATION', 'CREDIT_BALANCE_REFUND_REQUEST',
         'NOT_ATTRIBUTABLE_TO_CUSTOMER', 'PERSONAL_EMERGENCY_DURING_EXECUTION')),
    CONSTRAINT chk_refund_authorization_mode CHECK (authorization_mode IN ('TENANT_ADMINISTRATOR', 'AUTOMATIC_DETERMINATION')),
    CONSTRAINT chk_refund_authorization_amounts CHECK (
        potential_refund_value_cents > 0 AND authorized_amount_cents > 0 AND authorized_amount_cents <= potential_refund_value_cents),
    CONSTRAINT chk_refund_authorization_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT chk_refund_authorization_due CHECK (execution_due_at >= authorized_at),
    CONSTRAINT chk_refund_authorization_decision_reference CHECK (
        (refund_origin IN ('PENDING_TREATMENT', 'MODIFICATION_EXCESS', 'CUSTOMER_CANCELLATION', 'CREDIT_BALANCE_REFUND_REQUEST'))
        = (financial_decision_id IS NOT NULL)),
    CONSTRAINT chk_refund_authorization_author CHECK ((authorization_mode = 'TENANT_ADMINISTRATOR') = (authorized_by IS NOT NULL)),
    CONSTRAINT chk_refund_authorization_method CHECK (outflow_method IS NULL OR outflow_method IN ('TRANSFER', 'CASH')),
    CONSTRAINT chk_refund_authorization_execution_state CHECK (
        (execution_state = 'AUTHORIZED' AND executing_at IS NULL AND executed_by IS NULL AND outflow_method IS NULL
            AND executed_at IS NULL AND cash_movement_id IS NULL)
        OR (execution_state = 'EXECUTING' AND executing_at IS NOT NULL AND executed_by IS NOT NULL AND outflow_method IS NOT NULL
            AND executed_at IS NULL AND cash_movement_id IS NULL)
        OR (execution_state = 'EXECUTED' AND executing_at IS NOT NULL AND executed_by IS NOT NULL AND outflow_method IS NOT NULL
            AND executed_at IS NOT NULL AND cash_movement_id IS NOT NULL))
);
