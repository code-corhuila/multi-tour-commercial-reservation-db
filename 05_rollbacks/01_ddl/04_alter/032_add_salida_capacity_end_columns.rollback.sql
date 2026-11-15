ALTER TABLE commercial_reservation.salida_capacity
    DROP CONSTRAINT chk_salida_capacity_cancelled_at_status,
    DROP CONSTRAINT chk_salida_capacity_finalized_at_status,
    DROP COLUMN cancelled_at,
    DROP COLUMN finalized_at,
    DROP COLUMN estimated_ends_at;
