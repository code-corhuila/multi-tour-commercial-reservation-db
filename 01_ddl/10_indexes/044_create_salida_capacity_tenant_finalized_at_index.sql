-- HU-COM-019 (-db) plan D-06, AC-D19.9: first arm of the pre-filter of the retention run, the departures that ended (real end). Partial, so the hot rows stay small. Built CONCURRENTLY, as
-- the only statement of its changeset and outside a transaction, so the writes of the mirror are not blocked (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_salida_capacity_tenant_finalized_at ON commercial_reservation.salida_capacity (tenant_id, finalized_at) WHERE finalized_at IS NOT NULL;
