-- HU-COM-016 (-db) plan D-02, DP-D16-1 to DP-D16-4 (PROPOSED defaults): one row per 24-running-hour financial decision (financial_decisions of the dictionary).
-- Kind, outcome, author and instant are recorded once (RN-RES-006C); the guard that forbids editing a decided row is in 07_functions/006. The credit-balance
-- reference has no key until HU-COM-017 creates the table (G-B). Amounts are bigint cents, the remaining time is in minutes, and no column has a DEFAULT.
CREATE TABLE commercial_reservation.financial_decision (
    financial_decision_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_financial_decision_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_financial_decision_reservation_required NOT NULL,
    credit_balance_id uuid,
    decision_kind text CONSTRAINT chk_financial_decision_kind_required NOT NULL,
    base_amount_cents bigint CONSTRAINT chk_financial_decision_base_amount_required NOT NULL,
    penalty_amount_cents bigint,
    recognized_at timestamptz CONSTRAINT chk_financial_decision_recognized_at_required NOT NULL,
    frozen_at timestamptz,
    remaining_at_freeze_minutes integer,
    outcome text,
    decided_by_system boolean,
    decided_by uuid,
    decided_at timestamptz,
    rejection_justification text,
    CONSTRAINT pk_financial_decision PRIMARY KEY (financial_decision_id),
    CONSTRAINT fk_financial_decision_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_financial_decision_kind CHECK (decision_kind IN
        ('PENDING_TREATMENT', 'MODIFICATION_EXCESS', 'CUSTOMER_CANCELLATION', 'CREDIT_BALANCE_REFUND_REQUEST')),
    CONSTRAINT chk_financial_decision_base_positive CHECK (base_amount_cents > 0),
    CONSTRAINT chk_financial_decision_penalty CHECK (
        penalty_amount_cents IS NULL OR (penalty_amount_cents >= 0 AND decision_kind = 'CUSTOMER_CANCELLATION')),
    CONSTRAINT chk_financial_decision_credit_reference CHECK (
        (credit_balance_id IS NOT NULL) = (decision_kind = 'CREDIT_BALANCE_REFUND_REQUEST')),
    CONSTRAINT chk_financial_decision_outcome_kind CHECK (
        outcome IS NULL
        OR (decision_kind IN ('PENDING_TREATMENT', 'MODIFICATION_EXCESS', 'CUSTOMER_CANCELLATION')
            AND outcome IN ('REFUND_FULL', 'CREDIT_FULL'))
        OR (decision_kind = 'CREDIT_BALANCE_REFUND_REQUEST' AND outcome IN ('AUTHORIZED', 'REJECTED'))),
    CONSTRAINT chk_financial_decision_decided_coherent CHECK (
        (outcome IS NULL AND decided_at IS NULL AND decided_by_system IS NULL AND decided_by IS NULL)
        OR (outcome IS NOT NULL AND decided_at IS NOT NULL AND decided_by_system IS NOT NULL
            AND decided_by_system <> (decided_by IS NOT NULL))),
    CONSTRAINT chk_financial_decision_justification CHECK (
        (outcome = 'REJECTED' AND rejection_justification IS NOT NULL AND btrim(rejection_justification) <> '')
        OR ((outcome IS NULL OR outcome <> 'REJECTED') AND rejection_justification IS NULL)),
    CONSTRAINT chk_financial_decision_freeze CHECK (
        (frozen_at IS NULL AND remaining_at_freeze_minutes IS NULL)
        OR (frozen_at IS NOT NULL AND remaining_at_freeze_minutes IS NOT NULL AND remaining_at_freeze_minutes >= 0))
);
