-- HU-COM-013 (-db) plan D-04, RNF-D13.1: the read of the settlement of one reservation, led by the tenant. The table holds no row in any environment yet: no CONCURRENTLY.
CREATE INDEX idx_reservation_cancellation_tenant_reservation ON commercial_reservation.reservation_cancellation (tenant_id, reservation_id);
