-- HU-COM-019 (-db) plan D-06, AC-D19.8, AC-D19.9: the history of the deletions of a tenant, newest first. The record is new and empty: no CONCURRENTLY. The lookup by reservation is the primary key.
CREATE INDEX idx_sensitive_data_deletion_tenant_deleted_at ON commercial_reservation.sensitive_data_deletion (tenant_id, deleted_at DESC);
