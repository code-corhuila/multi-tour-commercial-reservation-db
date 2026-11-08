-- HU-COM-017 (-db) plan D-06, AC-D17.10: the credits of the reservations of a customer, led by the tenant. The table is small per tenant: no CONCURRENTLY.
CREATE INDEX idx_credit_balance_tenant_source_reservation ON commercial_reservation.credit_balance (tenant_id, source_reservation_id);
