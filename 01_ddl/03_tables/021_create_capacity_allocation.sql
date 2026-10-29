-- HU-COM-009 (-db) plan D-05, DP-D9-11 (PROPOSED, debt DD-4): the seats a reservation holds on a departure. held_seats of salida_capacity stays the authority
-- (DP-D9-3); each row here is its detail. salida_id has no foreign key: a cross-domain logical reference (Annex J.3.4). The key to reservation is simple
-- (DP-D9-12, debt DD-7). allocation_kind lists only RESERVATION now; HU-COM-018 widens it for the temporary hold of a reprogramming. The release time is
-- empty while held. expiresAt is not built (NO DEFINIDO). The one-active-hold rule is a partial unique index in 10_indexes/023.
CREATE TABLE commercial_reservation.capacity_allocation (
    capacity_allocation_id uuid NOT NULL,
    tenant_id uuid CONSTRAINT chk_capacity_allocation_tenant_required NOT NULL,
    salida_id uuid CONSTRAINT chk_capacity_allocation_salida_required NOT NULL,
    reservation_id uuid CONSTRAINT chk_capacity_allocation_reservation_required NOT NULL,
    party_size integer CONSTRAINT chk_capacity_allocation_party_size_required NOT NULL,
    allocation_kind text CONSTRAINT chk_capacity_allocation_kind_required NOT NULL DEFAULT 'RESERVATION',
    allocated_at timestamptz CONSTRAINT chk_capacity_allocation_allocated_at_required NOT NULL,
    released_at timestamptz,
    CONSTRAINT pk_capacity_allocation PRIMARY KEY (capacity_allocation_id),
    CONSTRAINT fk_capacity_allocation_reservation FOREIGN KEY (reservation_id)
        REFERENCES commercial_reservation.reservation (reservation_id) ON DELETE RESTRICT,
    CONSTRAINT chk_capacity_allocation_party_size CHECK (party_size > 0),
    CONSTRAINT chk_capacity_allocation_kind CHECK (allocation_kind IN ('RESERVATION'))
);
