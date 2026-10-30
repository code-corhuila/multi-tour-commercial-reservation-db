-- HU-COM-007 (-db) plan D-11: the reservations of a departure, for the per-departure count and the capacity reconciliation of HU-COM-009.
CREATE INDEX idx_reservation_tenant_salida ON commercial_reservation.reservation (tenant_id, salida_id);
