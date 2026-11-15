-- HU-COM-009 (-db) plan D-12: the attempts of a reservation, newest first (the history on the screens). The table is new and empty: no CONCURRENTLY.
CREATE INDEX idx_payment_attempt_tenant_reservation_registered_at ON commercial_reservation.payment_attempt (tenant_id, reservation_id, registered_at DESC);
