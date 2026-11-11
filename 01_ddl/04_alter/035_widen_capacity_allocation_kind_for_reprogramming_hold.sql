-- HU-COM-018 (-db) plan D-06, AC-D18.12 (DP-D18-5, PROPOSED default): the allocation learns the temporary hold of a reprogramming. The check is dropped and added again by its name with the two kinds.
-- The existing unique key of 021 is scoped to RESERVATION, so a hold may coexist with the seat of the cancelled departure until the saga releases it.
ALTER TABLE commercial_reservation.capacity_allocation DROP CONSTRAINT chk_capacity_allocation_kind,
    ADD CONSTRAINT chk_capacity_allocation_kind CHECK (allocation_kind IN ('RESERVATION', 'REPROGRAMMING_HOLD'));
