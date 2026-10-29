ALTER TABLE commercial_reservation.salida_capacity
    DROP CONSTRAINT chk_salida_capacity_status,
    DROP COLUMN status,
    DROP COLUMN hora_inicio;
