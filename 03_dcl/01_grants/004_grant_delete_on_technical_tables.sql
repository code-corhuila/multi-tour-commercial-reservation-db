-- The one exception to "never DELETE" (RN-06 protects the catalog, not these): ADR-004 D10 point 6
-- has the API purge old idempotency keys and published events daily, running as the application user.
-- Explicit and per table, so a table created later is still born without DELETE.
GRANT DELETE ON commercial_reservation.idempotency_key, commercial_reservation.outbox_event TO commercial_reservation_writer;
