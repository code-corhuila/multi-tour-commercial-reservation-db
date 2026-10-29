-- HU-COM-007 (-db) plan D-09 and D-11: the index of fk_outbox_event_reservation, like the other aggregate keys of the outbox (006, 008).
CREATE INDEX idx_outbox_event_reservation ON commercial_reservation.outbox_event (reservation_id);
