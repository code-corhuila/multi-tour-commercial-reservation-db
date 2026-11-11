ALTER TABLE commercial_reservation.capacity_allocation DROP CONSTRAINT chk_capacity_allocation_kind,
    ADD CONSTRAINT chk_capacity_allocation_kind CHECK (allocation_kind IN ('RESERVATION'));
