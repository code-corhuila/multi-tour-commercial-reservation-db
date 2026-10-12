-- Serves the management listing: the associations of one tenant, most recent first, with an optional filter
-- on the status. tenant_id leads so that no query can read across tenants.
CREATE INDEX idx_associated_establishment_tenant_status_created ON commercial_reservation.associated_establishment (tenant_id, association_status, created_at DESC);
