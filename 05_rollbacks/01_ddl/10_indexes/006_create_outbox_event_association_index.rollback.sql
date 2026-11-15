-- PROPUESTO (HU-COM-002 D-07): remove only the new association FK index.
DROP INDEX CONCURRENTLY commercial_reservation.idx_outbox_event_tenant_id_association_id;
