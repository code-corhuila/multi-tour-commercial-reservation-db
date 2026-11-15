-- The index of the capacity check (api plan D-05): the departures of one service inside one tenant, to
-- sum their held seats. tenant_id leads so that no query can read across tenants, and it also covers
-- the foreign key column (Annex A rule 3).
CREATE INDEX idx_salida_capacity_tenant_id_service_id ON commercial_reservation.salida_capacity (tenant_id, service_id);
