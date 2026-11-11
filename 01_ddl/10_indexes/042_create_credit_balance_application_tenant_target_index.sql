-- HU-COM-017 (-db) plan D-06, AC-D17.10: the applications received by one reservation and the foreign key to it, led by the tenant.
CREATE INDEX idx_credit_balance_application_tenant_target ON commercial_reservation.credit_balance_application (tenant_id, target_reservation_id);
