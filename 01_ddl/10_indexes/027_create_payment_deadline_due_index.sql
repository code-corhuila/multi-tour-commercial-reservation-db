-- HU-COM-011 (-db) plan D-06, RNF-D11.4: the due list of the expiry job is a range read of the unfrozen deadlines of a tenant by due instant. The table holds no
-- row in any environment yet: no CONCURRENTLY.
CREATE INDEX idx_payment_deadline_tenant_due_at ON commercial_reservation.payment_deadline (tenant_id, due_at) WHERE frozen_at IS NULL;
