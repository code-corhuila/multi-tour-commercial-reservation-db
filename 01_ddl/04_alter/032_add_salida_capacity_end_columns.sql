-- HU-COM-019 (-db) plan D-04, AC-D19.6 (DP-D19-3, PROPOSED default): the end of the service on the departure mirror. The estimated end, the real end and the cancellation instant are
-- nullable, because a row born before the consumer has no value and the mirror is born from the scheduling event, which carries only the estimated end. The real end needs status
-- FINALIZED and the cancellation instant needs status CANCELLED; the consumer writes the status and its instant in one statement. No DEFAULT.
ALTER TABLE commercial_reservation.salida_capacity
    ADD COLUMN estimated_ends_at timestamptz,
    ADD COLUMN finalized_at timestamptz,
    ADD COLUMN cancelled_at timestamptz,
    ADD CONSTRAINT chk_salida_capacity_finalized_at_status CHECK (finalized_at IS NULL OR status = 'FINALIZED'),
    ADD CONSTRAINT chk_salida_capacity_cancelled_at_status CHECK (cancelled_at IS NULL OR status = 'CANCELLED');
