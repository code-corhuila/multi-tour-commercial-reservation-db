-- HU-COM-013 (-db) plan D-02, DP-D13-1, DP-D13-2 (PROPOSED defaults): the settlement of a cancellation requested by the customer, one row per reservation,
-- written once and never edited. It keeps the reason (free text), the validated amount, the penalty percentage used in basis points and the amounts
-- (RN-RES-008: refundable = validated - penalty). No DEFAULT: the service states every value. The key to the reservation, which also holds the cause and the
-- tenant, arrives in 04_alter/025 together with the unique key it needs. Amounts are bigint cents.
CREATE TABLE commercial_reservation.reservation_cancellation (
    reservation_cancellation_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_reservation_cancellation_tenant_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_reservation_cancellation_reservation_required NOT NULL,
    cancellation_cause text CONSTRAINT chk_reservation_cancellation_cause_required NOT NULL,
    reason text CONSTRAINT chk_reservation_cancellation_reason_required NOT NULL,
    validated_amount_cents bigint CONSTRAINT chk_reservation_cancellation_validated_required NOT NULL,
    penalty_bp integer CONSTRAINT chk_reservation_cancellation_penalty_bp_required NOT NULL,
    penalty_amount_cents bigint CONSTRAINT chk_reservation_cancellation_penalty_required NOT NULL,
    refundable_amount_cents bigint CONSTRAINT chk_reservation_cancellation_refundable_required NOT NULL,
    registered_by uuid CONSTRAINT chk_reservation_cancellation_registered_by_required NOT NULL,
    registered_at timestamptz CONSTRAINT chk_reservation_cancellation_registered_at_required NOT NULL,
    CONSTRAINT pk_reservation_cancellation PRIMARY KEY (reservation_cancellation_id),
    CONSTRAINT uq_reservation_cancellation_reservation UNIQUE (reservation_id),
    CONSTRAINT chk_reservation_cancellation_cause CHECK (cancellation_cause = 'CUSTOMER_REQUEST'),
    CONSTRAINT chk_reservation_cancellation_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT chk_reservation_cancellation_penalty_bp CHECK (penalty_bp BETWEEN 0 AND 10000),
    CONSTRAINT chk_reservation_cancellation_amounts CHECK (
        validated_amount_cents >= 0 AND penalty_amount_cents >= 0 AND refundable_amount_cents >= 0
        AND penalty_amount_cents <= validated_amount_cents
        AND refundable_amount_cents = validated_amount_cents - penalty_amount_cents)
);
