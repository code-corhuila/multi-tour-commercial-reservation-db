CREATE INDEX idx_customer_tenant_account_id ON commercial_reservation.customer (tenant_id, account_id)
    WHERE account_id IS NOT NULL;
