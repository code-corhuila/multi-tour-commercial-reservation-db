-- The new FK's tenant-scoped access path, outside a transaction (Annex A rule 14).
CREATE INDEX CONCURRENTLY idx_outbox_event_tenant_id_discount_rule_id ON commercial_reservation.outbox_event (tenant_id, discount_rule_id);
