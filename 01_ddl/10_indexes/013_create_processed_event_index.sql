-- HU-COM-006 (-db) plan D-05: the 30-day purge of processed events deletes by age (RNF-D7).
CREATE INDEX idx_processed_event_processed_at ON commercial_reservation.processed_event (processed_at);
