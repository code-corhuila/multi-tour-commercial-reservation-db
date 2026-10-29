-- HU-COM-007 (-db) plan D-11: the active list of a tenant, newest first (AC-D7.15). The table is empty: no CONCURRENTLY (norm 5.2.7).
CREATE INDEX idx_reservation_tenant_status_created ON commercial_reservation.reservation (tenant_id, reservation_status, created_at DESC);
