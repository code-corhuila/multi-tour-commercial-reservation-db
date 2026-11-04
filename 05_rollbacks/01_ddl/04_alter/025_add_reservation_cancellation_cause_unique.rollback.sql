ALTER TABLE commercial_reservation.reservation_cancellation
    DROP CONSTRAINT fk_reservation_cancellation_reservation;
ALTER TABLE commercial_reservation.reservation
    DROP CONSTRAINT uq_reservation_tenant_id_cancellation_cause;
