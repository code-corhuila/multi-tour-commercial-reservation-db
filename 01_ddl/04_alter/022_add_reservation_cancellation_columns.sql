-- HU-COM-011 (-db) plan D-04, DP-D11-2 (PROPOSED default, debt DD-1): a cancelled reservation always carries its cause and instant; the canceller is null
-- when the system acted (the expiry). Any other reservation carries none of the three. No reservation is cancelled in any environment yet, so no validation step.
ALTER TABLE commercial_reservation.reservation
    ADD COLUMN cancellation_cause text,
    ADD COLUMN cancelled_at timestamptz,
    ADD COLUMN cancelled_by uuid,
    ADD CONSTRAINT chk_reservation_cancellation_cause CHECK (
        cancellation_cause IS NULL OR cancellation_cause IN ('PAYMENT_EXPIRY', 'CUSTOMER_REQUEST', 'NOT_ATTRIBUTABLE_TO_CUSTOMER')),
    ADD CONSTRAINT chk_reservation_cancellation_coherent CHECK (
        (reservation_status = 'CANCELLED' AND cancellation_cause IS NOT NULL AND cancelled_at IS NOT NULL)
        OR (reservation_status <> 'CANCELLED' AND cancellation_cause IS NULL AND cancelled_at IS NULL AND cancelled_by IS NULL));
