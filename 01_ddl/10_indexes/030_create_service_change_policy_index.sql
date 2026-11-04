-- HU-COM-012 (-db) plan D-06: the index of the foreign key to the tour, led by the tenant (Annex A). The unique of 03_tables/028 serves the read by type.
-- The table is new and empty: no CONCURRENTLY.
CREATE INDEX idx_service_change_policy_tenant_service
    ON commercial_reservation.service_change_policy (tenant_id, service_id);
