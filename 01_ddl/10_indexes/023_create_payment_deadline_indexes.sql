-- HU-COM-009 (-db) plan D-12, D-13: at most one initial deadline per reservation, the expiry reads of HU-COM-011 by tenant and due instant, and the index
-- of the foreign key to the reservation (Annex A). The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_payment_deadline_initial_reservation ON commercial_reservation.payment_deadline (tenant_id, reservation_id)
    WHERE deadline_kind = 'INITIAL_PAYMENT';
CREATE INDEX idx_payment_deadline_tenant_due ON commercial_reservation.payment_deadline (tenant_id, due_at);
CREATE INDEX idx_payment_deadline_reservation_id ON commercial_reservation.payment_deadline (reservation_id);
