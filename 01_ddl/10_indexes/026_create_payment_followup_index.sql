-- HU-COM-011 (-db) plan D-06: the follow-up history of one reservation, newest first, inside a tenant. The table is new and empty: no CONCURRENTLY.
CREATE INDEX idx_payment_followup_tenant_reservation_contacted_at
    ON commercial_reservation.payment_followup (tenant_id, reservation_id, contacted_at DESC);
