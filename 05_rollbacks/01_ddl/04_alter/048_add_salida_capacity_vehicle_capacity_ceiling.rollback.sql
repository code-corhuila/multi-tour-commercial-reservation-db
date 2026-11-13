ALTER TABLE commercial_reservation.salida_capacity
    DROP CONSTRAINT chk_salida_capacity_vehicle_capacity_ceiling,
    DROP COLUMN vehicle_capacity_ceiling;
