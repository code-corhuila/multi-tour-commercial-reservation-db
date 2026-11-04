-- HU-COM-012 (-db) plan D-06: the history of one reservation, newest first, inside a tenant. The table is new and empty: no CONCURRENTLY.
CREATE INDEX idx_reservation_modification_tenant_reservation_registered_at
    ON commercial_reservation.reservation_modification (tenant_id, reservation_id, registered_at DESC);
