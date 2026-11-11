-- HU-COM-017 (-db) plan D-06, AC-D17.10: the history of the applications of one credit and the sums of the guards, led by the tenant.
CREATE INDEX idx_credit_balance_application_tenant_credit ON commercial_reservation.credit_balance_application (tenant_id, credit_balance_id);
