-- HU-COM-006 (-db) plan D-04: the open departures of one tour of one tenant, ordered by start (AC-D6.4). tenant_id leads so that
-- no query can read across tenants. The status is not in the index: a tour has a handful of departures. A plain CREATE INDEX
-- because the table is small and empty at first, as the earlier indexes of this table.
CREATE INDEX idx_salida_capacity_tenant_service_start ON commercial_reservation.salida_capacity (tenant_id, service_id, hora_inicio);
