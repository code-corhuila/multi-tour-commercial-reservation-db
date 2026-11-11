-- HU-COM-010 (-db) plan D-06 (PROPOSED): the list "pending payments" of a tenant, the overdue filter and the count of the badge. Partial, on the small hot
-- set of proofs under validation. Built CONCURRENTLY, the only statement of its changeset and outside a transaction, because the table already holds rows
-- in a running environment (norm 5.2.7, fix #14). The history of a reservation is served by the index of HU-COM-009; no second index for it.
CREATE INDEX CONCURRENTLY idx_payment_attempt_tenant_under_validation ON commercial_reservation.payment_attempt (tenant_id, registered_at)
    WHERE validation_status = 'IN_VALIDATION';
