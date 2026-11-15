-- Serves the management and offer listings: the services of one tenant, most recent first, with an
-- optional filter on the status. tenant_id leads so that no query can read across tenants.
CREATE INDEX idx_catalog_service_tenant_status_created ON commercial_reservation.catalog_service (tenant_id, catalog_status, created_at DESC);

-- Every foreign key column is indexed (Annex A rule 3): without it, checking the key on each
-- catalog change would scan the whole outbox. 001 does not cover it.
CREATE INDEX idx_outbox_event_service_id ON commercial_reservation.outbox_event (service_id);
