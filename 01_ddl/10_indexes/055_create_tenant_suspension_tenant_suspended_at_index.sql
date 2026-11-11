-- HU-COM-020 (-db) plan D-05, AC-D20.10: the intervals of a tenant that touch a window, newest first, led by the tenant.
CREATE INDEX idx_tenant_suspension_tenant_suspended_at ON commercial_reservation.tenant_suspension (tenant_id, suspended_at DESC);
