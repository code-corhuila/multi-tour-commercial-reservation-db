-- PROPUESTO (HU-COM-002 D-07): cover the new association FK, led by tenant_id.
CREATE INDEX CONCURRENTLY idx_outbox_event_tenant_id_association_id
    ON commercial_reservation.outbox_event (tenant_id, association_id);
