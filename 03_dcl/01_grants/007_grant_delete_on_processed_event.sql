-- HU-COM-006 (-db) plan D-05, AC-D6.9: the third technical table whose rows the application purges (ADR-004 D4 and RNF-D7), the
-- same exception that 004 made for idempotency_key and outbox_event. Explicit and per table; no business table receives DELETE.
GRANT DELETE ON commercial_reservation.processed_event TO commercial_reservation_writer;
