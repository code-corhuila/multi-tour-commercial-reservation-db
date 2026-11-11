-- HU-COM-019 (-db) plan D-06, AC-D19.9: third arm of the pre-filter, the cancelled departures (the year counts from the cancellation when the closing is blocked). Partial, built
-- CONCURRENTLY, alone and outside a transaction (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_salida_capacity_tenant_cancelled_at ON commercial_reservation.salida_capacity (tenant_id, cancelled_at) WHERE cancelled_at IS NOT NULL;
