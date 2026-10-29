-- HU-COM-007 (-db) plan D-11: the reservations of a customer, newest first ("my reservations" of HU-COM-008).
CREATE INDEX idx_reservation_tenant_customer_created ON commercial_reservation.reservation (tenant_id, customer_id, created_at DESC);
