-- HU-COM-018 (-db) plan D-06, AC-D18.12 (K3): one active hold per reservation, led by the tenant.
CREATE UNIQUE INDEX uq_capacity_allocation_reprogramming_hold ON commercial_reservation.capacity_allocation (tenant_id, reservation_id) WHERE allocation_kind = 'REPROGRAMMING_HOLD' AND released_at IS NULL;
