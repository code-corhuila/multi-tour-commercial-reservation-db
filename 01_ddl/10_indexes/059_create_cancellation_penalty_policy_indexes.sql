-- HU-COM-013 (-db) DP-02a (PROPOSED): one row per tenant at the tenant level, one per tenant and service at the service level, and the index of the service
-- foreign key (Annex A). The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_cancellation_penalty_policy_tenant ON commercial_reservation.cancellation_penalty_policy (tenant_id)
    WHERE service_id IS NULL;
CREATE UNIQUE INDEX uq_cancellation_penalty_policy_tenant_service ON commercial_reservation.cancellation_penalty_policy (tenant_id, service_id)
    WHERE service_id IS NOT NULL;
CREATE INDEX idx_cancellation_penalty_policy_service_id ON commercial_reservation.cancellation_penalty_policy (service_id);
