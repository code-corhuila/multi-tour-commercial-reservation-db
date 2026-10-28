-- HU-COM-005 (-db) DP-D5-4: look up the customer of a verified account inside a tenant. Partial, because
-- the column is empty until AccountEmailVerified arrives. The table is empty: no CONCURRENTLY (norm 5.2.7).
CREATE INDEX idx_customer_tenant_account_id ON commercial_reservation.customer (tenant_id, account_id)
    WHERE account_id IS NOT NULL;
