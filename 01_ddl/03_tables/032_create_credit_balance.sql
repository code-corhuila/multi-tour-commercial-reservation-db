-- HU-COM-017 (-db) plan D-02, DP-D17-2 (PROPOSED defaults): one row per recorded credit balance (credit_balances of the dictionary). The credit outlives the
-- reservation it came from and belongs to the customer of that reservation, so it is its own table. The source is one decision or one payment attempt, never both.
-- Amounts are bigint cents; no DEFAULT. UPDATE is withdrawn in 03_dcl/01_grants/015 and DELETE was never granted. The keys to reservation, decision and attempt restrict.
CREATE TABLE commercial_reservation.credit_balance (
    credit_balance_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_credit_balance_tenant_required NOT NULL,
    source_reservation_id uuid CONSTRAINT chk_credit_balance_reservation_required NOT NULL,
    credit_origin text CONSTRAINT chk_credit_balance_origin_required NOT NULL,
    amount_cents bigint CONSTRAINT chk_credit_balance_amount_required NOT NULL,
    source_financial_decision_id uuid,
    source_payment_attempt_id uuid,
    recorded_at timestamptz CONSTRAINT chk_credit_balance_recorded_at_required NOT NULL,
    recorded_by uuid CONSTRAINT chk_credit_balance_recorded_by_required NOT NULL,
    CONSTRAINT pk_credit_balance PRIMARY KEY (credit_balance_id),
    CONSTRAINT fk_credit_balance_reservation FOREIGN KEY (source_reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT fk_credit_balance_decision FOREIGN KEY (source_financial_decision_id)
        REFERENCES commercial_reservation.financial_decision (financial_decision_id) ON DELETE RESTRICT,
    CONSTRAINT fk_credit_balance_payment_attempt FOREIGN KEY (source_payment_attempt_id)
        REFERENCES commercial_reservation.payment_attempt (payment_attempt_id) ON DELETE RESTRICT,
    CONSTRAINT chk_credit_balance_origin CHECK (credit_origin IN
        ('PENDING_TREATMENT', 'MODIFICATION_EXCESS', 'CUSTOMER_CANCELLATION', 'PAYMENT_EXCESS')),
    CONSTRAINT chk_credit_balance_amount_positive CHECK (amount_cents > 0),
    CONSTRAINT chk_credit_balance_source CHECK (
        (credit_origin = 'PAYMENT_EXCESS' AND source_payment_attempt_id IS NOT NULL AND source_financial_decision_id IS NULL)
        OR (credit_origin <> 'PAYMENT_EXCESS' AND source_financial_decision_id IS NOT NULL AND source_payment_attempt_id IS NULL))
);
