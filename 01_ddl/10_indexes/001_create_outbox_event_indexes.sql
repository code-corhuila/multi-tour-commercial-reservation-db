CREATE INDEX idx_outbox_event_tenant_id ON commercial_reservation.outbox_event (tenant_id);

-- The relay asks for the oldest events not yet published. Partial, so it stays small while published
-- rows pile up behind it.
CREATE INDEX idx_outbox_event_unpublished ON commercial_reservation.outbox_event (occurred_at) WHERE published_at IS NULL;
