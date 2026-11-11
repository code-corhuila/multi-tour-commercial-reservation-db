ALTER TABLE commercial_reservation.reservation
    DROP CONSTRAINT chk_reservation_cancellation_coherent,
    DROP CONSTRAINT chk_reservation_cancellation_cause,
    DROP COLUMN cancelled_by,
    DROP COLUMN cancelled_at,
    DROP COLUMN cancellation_cause;
