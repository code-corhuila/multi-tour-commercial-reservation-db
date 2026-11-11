-- HU-COM-009 (-db) plan D-05, DP-D9-3 (PROPOSED, debt DD-4): held seats never exceed the effective capacity of a departure. The conditional update of the
-- -api relies on this invariant; the CHECK is the only guard against a write around the service (ADR-004 D4). Added NOT VALID and validated in the same
-- changeset, so a row already above its capacity in any environment fails the deploy visibly. The earlier check (held_seats >= 0) is untouched.
ALTER TABLE commercial_reservation.salida_capacity
    ADD CONSTRAINT chk_salida_capacity_held_within_effective CHECK (held_seats <= effective_capacity) NOT VALID;
ALTER TABLE commercial_reservation.salida_capacity VALIDATE CONSTRAINT chk_salida_capacity_held_within_effective;
