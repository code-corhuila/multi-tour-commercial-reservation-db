-- HU-COM-019 (-db) plan D-06, AC-D19.9: second arm of the pre-filter, the departures not finalized or cancelled whose estimated end passed (the anchor after 7 days without regularization).
-- Partial on the status. Built CONCURRENTLY, alone and outside a transaction (norm 5.2.7). If a failed build left an invalid index, drop it before the retry.
CREATE INDEX CONCURRENTLY idx_salida_capacity_tenant_estimated_end ON commercial_reservation.salida_capacity (tenant_id, estimated_ends_at) WHERE status NOT IN ('FINALIZED', 'CANCELLED');
