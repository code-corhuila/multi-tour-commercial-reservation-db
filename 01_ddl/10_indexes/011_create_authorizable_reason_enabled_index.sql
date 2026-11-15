-- HU-COM-004 (-db): the reasons a tenant can choose are the enabled ones; the partial index keeps that listing small.
-- Outside a transaction (Annex A rule 14), like the other indexes.
CREATE INDEX CONCURRENTLY idx_authorizable_reason_tenant_enabled ON commercial_reservation.authorizable_reason (tenant_id) WHERE status = 'ENABLED';
