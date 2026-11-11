-- HU-COM-009 (-db) docs issue #175, plan D-03 (PROPOSED, debt DD-2): one payment attempt, the registration columns only. The review
-- columns (who decided, when, with which amounts) are added by HU-COM-010. Money is bigint cents. The closed lists hold English codes (DP-D9-7).
-- Transfer carries a validation status, cash carries none (DP-D9-1). payment_status_snapshot is the financial situation after the registration.
-- registered_by is a new field (PROPOSED): the dictionary has none and RN-RES-006D needs the trace. The key to reservation is simple
-- (DP-D9-12): the engine refuses an orphan, the adapter refuses another tenant's reservation (debt DD-7). Nothing has a DEFAULT.
-- Default writer privileges give SELECT/INSERT/UPDATE and never DELETE (AC-D9.14).
CREATE TABLE commercial_reservation.payment_attempt (
    payment_attempt_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_payment_attempt_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_payment_attempt_reservation_required NOT NULL,
    payment_method text CONSTRAINT chk_payment_attempt_method_required NOT NULL,
    received_amount_cents bigint CONSTRAINT chk_payment_attempt_received_amount_required NOT NULL,
    validation_status text,
    payment_status_snapshot text CONSTRAINT chk_payment_attempt_payment_status_snapshot_required NOT NULL,
    registered_by uuid CONSTRAINT chk_payment_attempt_registered_by_required NOT NULL,
    registered_at timestamptz CONSTRAINT chk_payment_attempt_registered_at_required NOT NULL,
    CONSTRAINT pk_payment_attempt PRIMARY KEY (payment_attempt_id),
    CONSTRAINT fk_payment_attempt_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_payment_attempt_amount_positive CHECK (received_amount_cents > 0),
    CONSTRAINT chk_payment_attempt_method CHECK (payment_method IN ('TRANSFER', 'CASH')),
    CONSTRAINT chk_payment_attempt_status_matches_method CHECK (
        (payment_method = 'TRANSFER' AND validation_status IS NOT NULL AND validation_status IN ('IN_VALIDATION', 'APPROVED', 'REJECTED'))
        OR (payment_method = 'CASH' AND validation_status IS NULL)),
    CONSTRAINT chk_payment_attempt_payment_status_snapshot CHECK (
        payment_status_snapshot IN ('NO_PAYMENT', 'PARTIAL', 'DEPOSIT_RECEIVED', 'BALANCE_PENDING', 'FULLY_PAID'))
);
