-- Tenant listing and the real query of rules in force (HU-COM-003 D-08).
CREATE INDEX CONCURRENTLY idx_discount_rule_tenant_id ON commercial_reservation.discount_rule (tenant_id);
CREATE INDEX CONCURRENTLY idx_discount_rule_tenant_validity ON commercial_reservation.discount_rule (tenant_id, starts_on, ends_on);
