-- HU-COM-009 (-db) plan D-05 and D-12: one active allocation of the reservation kind per reservation (a later payment does not hold again, an increase of
-- travellers updates party_size of that row); the active allocations of a departure; and the index of the foreign key to the reservation (Annex A).
-- The table is new and empty: no CONCURRENTLY.
CREATE UNIQUE INDEX uq_capacity_allocation_active_reservation ON commercial_reservation.capacity_allocation (tenant_id, reservation_id)
    WHERE released_at IS NULL AND allocation_kind = 'RESERVATION';
CREATE INDEX idx_capacity_allocation_tenant_salida_active ON commercial_reservation.capacity_allocation (tenant_id, salida_id)
    WHERE released_at IS NULL;
CREATE INDEX idx_capacity_allocation_reservation_id ON commercial_reservation.capacity_allocation (reservation_id);
