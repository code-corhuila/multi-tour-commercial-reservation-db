-- HU-COM-002 (-db) spec 2026-11-12 (AC-D2.12): the change log of a tenant, newest first. tenant_id leads so that no query can read across tenants.
CREATE INDEX idx_associated_establishment_change_tenant_occurred ON commercial_reservation.associated_establishment_change (tenant_id, occurred_at DESC);
