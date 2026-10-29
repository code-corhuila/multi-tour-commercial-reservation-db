-- HU-COM-009 (-db) plan D-11, D-12 and DP-D9-6 (PROPOSED): one row per tenant and type at the tenant level, one per tenant, service and type at the service
-- level, the parameters of a tenant, and the index of the service foreign key (Annex A). The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_payment_condition_tenant_payment_type ON commercial_reservation.payment_condition (tenant_id, payment_type)
    WHERE service_id IS NULL;
CREATE UNIQUE INDEX uq_payment_condition_tenant_service_payment_type ON commercial_reservation.payment_condition (tenant_id, service_id, payment_type)
    WHERE service_id IS NOT NULL;
CREATE INDEX idx_payment_condition_tenant ON commercial_reservation.payment_condition (tenant_id, payment_type);
CREATE INDEX idx_payment_condition_service_id ON commercial_reservation.payment_condition (service_id);
